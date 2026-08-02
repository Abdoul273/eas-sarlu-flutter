import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../auth/auth_state.dart';
import '../db/app_database.dart' show OpQueueData, ConflitsCompanion;
import '../db/stores.dart';
import '../reseau.dart';
import '../models/activite.dart';
import '../models/models.dart';
import '../../features/activite/notifications_provider.dart';
import 'op_queue.dart';
import 'sync_state.dart';

// ─── Moteur de synchronisation ────────────────────────────────────────────────
// Le magasin travaille hors ligne par défaut : tout est écrit sur le téléphone,
// et ce moteur se contente de rattraper le serveur quand le réseau revient.
//
// Il est piloté par des ÉVÉNEMENTS — retour du réseau, retour au premier plan,
// nouvelle opération déposée — et non par un minuteur serré. La version
// précédente relançait un cycle complet toutes les cinq secondes, soit plus de
// sept cents requêtes par heure sur une connexion mobile de Conakry, pour ne
// rien apprendre la plupart du temps. Il reste un battement lent, seule façon
// de voir arriver les modifications faites depuis l'application web.

/// Battement de fond quand l'application est à l'écran.
///
/// Vingt secondes : c'est ce qui fait qu'un droit retiré depuis l'application
/// web s'applique ici « tout de suite » plutôt qu'au prochain redémarrage. Le
/// battement n'interroge que `/data/version`, une lecture minuscule ; ce n'est
/// que si la version a bougé qu'on rapatrie les données. Le coût réel est donc
/// de quelques kilo-octets par heure, même sur une connexion de Conakry.
const _battementActif = Duration(seconds: 20);

/// Battement quand elle est en arrière-plan. Le système finit de toute façon
/// par suspendre les minuteurs ; inutile d'insister.
const _battementInactif = Duration(minutes: 15);

/// Un lot de plus de cent opérations produit une requête que le serveur met
/// trop longtemps à traiter, et qui expire avant d'aboutir — la file repart
/// alors du début, indéfiniment. On la pousse par tranches.
const int _taillePaquet = 50;

/// Délai après lequel une nouvelle opération déclenche l'envoi.
///
/// Une vente, c'est plusieurs écritures coup sur coup (vente, facture,
/// mouvements de stock). Sans ce court regroupement, chacune partait dans sa
/// propre requête.
const _regroupement = Duration(seconds: 2);

class SyncEngine {
  final ApiClient _apiClient;
  final Stores _stores;
  final OpQueue _opQueue;
  final RegistreConflits _conflits;
  final SyncStateNotifier _syncState;
  final Connectivity _connectivity;

  /// Prévenu à chaque instantané reçu du serveur, avec la liste des comptes.
  ///
  /// C'est par là que les droits du compte connecté sont rafraîchis sans
  /// redémarrage : le moteur ne connaît pas l'authentification, il se contente
  /// de transmettre ce que le serveur vient de dire.
  final Future<void> Function(List<Utilisateur>)? onUtilisateurs;

  /// Prévenu du journal d'activité contenu dans le même instantané.
  ///
  /// C'est ce qui alimente les notifications, sans une seule requête de plus :
  /// `/data/all` porte déjà le journal, et n'est rapatrié que lorsque la
  /// version des données a bougé. Le fil de notifications interrogeait
  /// auparavant `/data/activites` pour son compte, toutes les vingt secondes.
  final Future<void> Function(List<ActiviteEntree>)? onActivites;

  Timer? _battement;
  Timer? _regroupementTimer;
  bool _enCours = false;

  /// Une demande est arrivée pendant un cycle : on en refera un juste après.
  /// Sans ce drapeau, une vente saisie pendant une synchronisation attendait le
  /// battement suivant.
  bool _demandeEnAttente = false;

  /// Messages des opérations refusées faute de droit, pendant le cycle en
  /// cours. Vidé à chaque cycle : ils sont remontés à l'utilisateur une fois.
  final Set<String> _refusRecus = {};

  bool _demarre = false;
  StreamSubscription? _abonnementReseau;
  StreamSubscription? _abonnementFile;
  AppLifecycleState _etatApp = AppLifecycleState.resumed;

  SyncEngine({
    required ApiClient apiClient,
    required Stores stores,
    required OpQueue opQueue,
    required RegistreConflits conflits,
    required SyncStateNotifier syncState,
    required Connectivity connectivity,
    this.onUtilisateurs,
    this.onActivites,
  })  : _apiClient = apiClient,
        _stores = stores,
        _opQueue = opQueue,
        _conflits = conflits,
        _syncState = syncState,
        _connectivity = connectivity;

  /// Démarre le moteur. Appelable plusieurs fois sans dommage : l'état
  /// d'authentification change à chaque revalidation en arrière-plan, et
  /// chaque appel ajoutait auparavant un abonnement et un minuteur de plus.
  void start() {
    if (_demarre) return;
    _demarre = true;

    _abonnementReseau = _connectivity.onConnectivityChanged.listen((resultats) {
      if (estConnecte(resultats)) demanderSynchro();
    });

    // Une opération déposée dans la file déclenche l'envoi, après un court
    // regroupement. C'est ce qui remplace le minuteur de cinq secondes.
    _abonnementFile = _opQueue.watchPendingCount().listen((nombre) {
      if (nombre > 0) _programmerRegroupement();
    });

    _programmerBattement();
    demanderSynchro();
  }

  void stop() {
    _demarre = false;
    _abonnementReseau?.cancel();
    _abonnementReseau = null;
    _abonnementFile?.cancel();
    _abonnementFile = null;
    _battement?.cancel();
    _battement = null;
    _regroupementTimer?.cancel();
    _regroupementTimer = null;
  }

  void onAppLifecycleChange(AppLifecycleState state) {
    final revient =
        _etatApp != AppLifecycleState.resumed && state == AppLifecycleState.resumed;
    _etatApp = state;
    if (!_demarre) return;
    _programmerBattement();
    // Au retour à l'écran, on rattrape ce qui a bougé pendant l'absence.
    if (revient) demanderSynchro();
  }

  /// Demande un cycle. Si un cycle tourne déjà, on en programme un à sa suite
  /// plutôt que d'abandonner la demande.
  void demanderSynchro() {
    if (_enCours) {
      _demandeEnAttente = true;
      return;
    }
    unawaited(_cycle());
  }

  /// Cycle immédiat, attendu par l'appelant. Utilisé par le geste « tirer pour
  /// rafraîchir ».
  Future<void> forceSyncCycle() async {
    if (_enCours) {
      _demandeEnAttente = true;
      return;
    }
    await _cycle();
  }

  void _programmerBattement() {
    _battement?.cancel();
    final periode = _etatApp == AppLifecycleState.resumed
        ? _battementActif
        : _battementInactif;
    _battement = Timer.periodic(periode, (_) => demanderSynchro());
  }

  void _programmerRegroupement() {
    _regroupementTimer?.cancel();
    _regroupementTimer = Timer(_regroupement, demanderSynchro);
  }

  Future<void> _cycle() async {
    if (_enCours) return;
    _enCours = true;
    try {
      if (!await _reseauDisponible()) {
        _syncState.updateStatus(SyncStatus.offline);
        return;
      }

      _syncState.updateStatus(SyncStatus.syncing);

      _refusRecus.clear();

      // On pousse d'abord : les saisies du magasin passent avant la
      // récupération des modifications d'autrui. En cas de coupure au milieu
      // du cycle, c'est le travail local qui aura été sauvé.
      final aPousse = await _pousser();

      // Un refus force la reprise de l'instantané, même si rien n'a été
      // appliqué : c'est ce qui efface de l'écran l'opération que le serveur
      // n'a pas voulue.
      await _tirerSiNecessaire(forcer: aPousse || _refusRecus.isNotEmpty);

      if (_refusRecus.isNotEmpty) {
        _syncState.signalerRefus(_refusRecus.toList());
      }

      final restantes = await _opQueue.getAllOperations();
      final bloquees = restantes.where((o) => o.bloquee).length;
      if (bloquees > 0) {
        _syncState.updateStatus(SyncStatus.error,
            errorMessage:
                '$bloquees opération${bloquees > 1 ? 's' : ''} bloquée${bloquees > 1 ? 's' : ''}');
      } else if ((await _conflits.tous()).isNotEmpty) {
        _syncState.updateStatus(SyncStatus.conflict);
      } else {
        // « idle » même s'il reste des opérations temporisées : elles
        // repartiront seules, ce n'est pas une erreur. Le compteur en attente
        // le dit déjà.
        _syncState.updateStatus(SyncStatus.idle);
      }
    } on ApiException catch (e) {
      _syncState.updateStatus(SyncStatus.error, errorMessage: e.message);
    } catch (e) {
      _syncState.updateStatus(SyncStatus.error, errorMessage: e.toString());
    } finally {
      _enCours = false;
      if (_demandeEnAttente) {
        _demandeEnAttente = false;
        unawaited(_cycle());
      }
    }
  }

  /// Le réseau est-il réellement utilisable ?
  ///
  /// `connectivity_plus` répond « connecté » dès qu'une interface est active —
  /// un wifi de restaurant qui n'a pas d'accès sortant compris. Toutes les
  /// requêtes partaient alors pour expirer une à une. On confirme par un appel
  /// à `/health`, qui est court et sans authentification.
  Future<bool> _reseauDisponible() async {
    if (!estConnecte(await _connectivity.checkConnectivity())) return false;
    return _apiClient.sante();
  }

  // ── Envoi ──────────────────────────────────────────────────────────────────

  /// Pousse la file par tranches. Retourne vrai si au moins une opération a été
  /// acceptée — auquel cas la version du serveur a bougé de notre fait.
  Future<bool> _pousser() async {
    var quelqueChoseApplique = false;

    while (true) {
      final enAttente = await _opQueue.getPendingOperations();
      if (enAttente.isEmpty) break;

      final paquet = enAttente.take(_taillePaquet).toList();
      final opsNormales = <OpQueueData>[];

      for (final op in paquet) {
        if (op.type == 'entreprise') {
          try {
            final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;
            final entData = payload['record'] ?? payload;
            final resp = await _apiClient.dio.post(kDataEntreprise, data: entData);
            final respMap = resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null;
            final entRes = respMap?['entreprise'] ?? respMap?['record'];
            if (entRes != null && entRes is Map<String, dynamic>) {
              final existingEnt = await _stores.getEntreprise();
              if (existingEnt != null) {
                final mergedJson = {
                  ...existingEnt.toJson(),
                  if (entRes['_rev'] != null) '_rev': entRes['_rev'],
                  if (entRes['_updatedAt'] != null) '_updatedAt': entRes['_updatedAt'],
                  if (entRes['_updatedBy'] != null) '_updatedBy': entRes['_updatedBy'],
                };
                // Si le serveur a renvoyé un logo, on l'utilise, sinon on garde le local.
                if (entRes['logo'] != null && entRes['logo'].toString().isNotEmpty) {
                  mergedJson['logo'] = entRes['logo'];
                }
                if (entRes['signatureImage'] != null && entRes['signatureImage'].toString().isNotEmpty) {
                  mergedJson['signatureImage'] = entRes['signatureImage'];
                }
                await _stores.upsert('entreprise', Entreprise.fromJson(mergedJson));
              } else {
                await _stores.upsert('entreprise', Entreprise.fromJson(entRes));
              }
            }
            await _opQueue.markApplied(op.id);
            quelqueChoseApplique = true;
          } catch (e) {
            await _opQueue.markFailed(op.id, 'Erreur de synchronisation entreprise: $e');
          }
        } else {
          opsNormales.add(op);
        }
      }

      if (opsNormales.isNotEmpty) {
        final operations = opsNormales
            .map((op) => {
                  'id': op.id,
                  'type': op.type,
                  // Le serveur horodate le journal d'activité avec ce champ :
                  // sans lui, une opération saisie hors ligne serait journalisée
                  // sans date.
                  'timestamp': op.timestamp,
                  'payload': jsonDecode(op.payloadJson),
                })
            .toList();

        final reponse = await _apiClient.dio
            .post(kDataSync, data: {'operations': operations});
        final resultats =
            (reponse.data['resultats'] as List?) ?? const <dynamic>[];

        // Une opération dont le serveur ne dit rien reste dans la file. C'est le
        // cas d'une réponse tronquée : on préfère un doublon possible — que
        // l'idempotence du serveur rattrape grâce à l'identifiant d'opération —
        // à une vente perdue.
        final traitees = <String>{};
        final nouveauxConflits = <ConflitsCompanion>[];

        for (final brut in resultats) {
          final resultat = Map<String, dynamic>.from(brut as Map);
          final id = resultat['id'] as String;
          traitees.add(id);
          final applique = await _traiterResultat(paquet, resultat, nouveauxConflits);
          if (applique) quelqueChoseApplique = true;
        }

        await _conflits.ajouter(nouveauxConflits);
      }

      // Aucune des opérations envoyées n'a bougé : insister ferait tourner la
      // boucle indéfiniment sur le même paquet.
      final progression = paquet.any((op) => op.type == 'entreprise' || opsNormales.any((o) => o.id == op.id));
      if (!progression) break;
      if (enAttente.length <= _taillePaquet) break;
    }

    return quelqueChoseApplique;
  }

  /// Traite un résultat renvoyé par `/data/sync`. Retourne vrai si l'opération
  /// a été appliquée côté serveur.
  Future<bool> _traiterResultat(List<OpQueueData> paquet,
      Map<String, dynamic> resultat, List<ConflitsCompanion> conflits) async {
    final id = resultat['id'] as String;
    final statut = resultat['statut'] as String? ?? 'inconnu';
    final type = resultat['type'] as String? ?? '';

    switch (statut) {
      case 'applique':
      case 'deja_applique':
        // Le serveur place ses données sous « result ». C'est par là qu'arrivent
        // les numéros de document (VTE/FAC/DEP) qu'il attribue lui-même, ainsi
        // que les « _rev » à jour indispensables aux prochaines écritures.
        await _fusionnerDepuisServeur(type, resultat['result']);
        await _opQueue.markApplied(id);
        return true;

      case 'conflit':
        // L'opération SORT de la file. La rejouer referait échouer la
        // synchronisation à chaque retour de réseau sans jamais rien résoudre,
        // et bloquerait derrière elle toutes les ventes suivantes. Elle est
        // déposée dans le registre des conflits, où elle attend un arbitrage —
        // rien n'est jeté sans que l'utilisateur l'ait vu. C'est exactement ce
        // que fait l'application web.
        final op = _retrouver(paquet, id);
        conflits.add(ConflitsCompanion.insert(
          id: id,
          type: type,
          libelle: op?.libelle ?? _libelleParDefaut(type),
          // On conserve la charge utile LOCALE, et non le champ « tentative »
          // du serveur : c'est elle, et elle seule, qui peut être remise dans
          // la file si l'utilisateur choisit de garder sa version.
          tentativeJson: op?.payloadJson ?? '{}',
          serveurJson: jsonEncode(resultat['current'] ?? {}),
          detecteLe: DateTime.now().toIso8601String(),
        ));
        await _opQueue.markApplied(id);
        return false;

      case 'refuse':
        // Le serveur refuse l'opération faute de droit. C'est définitif : la
        // rejouer à chaque retour de réseau ne ferait que bloquer la file
        // derrière elle, indéfiniment, sans jamais aboutir.
        //
        // Elle sort donc de la file, et l'effet local qu'elle avait déjà produit
        // — une vente qui a décrémenté le stock, par exemple — est annulé en
        // reprenant l'instantané du serveur : c'est lui qui dit la vérité, et
        // laisser l'écran montrer une vente que le serveur n'a jamais acceptée
        // serait pire que le refus lui-même.
        await _opQueue.markApplied(id);
        _refusRecus.add(resultat['erreur']?.toString() ??
            "Vous n'avez pas le droit d'effectuer cette opération.");
        return false;

      case 'echec':
        await _opQueue.markFailed(
            id, resultat['erreur']?.toString() ?? 'Erreur inconnue');
        return false;

      case 'inconnu':
        // Le serveur ne connaît pas ce type d'opération : c'est qu'il n'a pas
        // encore été déployé avec la fonctionnalité qui l'émet. Le réessayer
        // n'y changera rien tant que le déploiement n'a pas eu lieu — mais il
        // n'y a rien de perdu non plus : l'opération reste dans la file, et le
        // bouton « Reprendre » du panneau de synchronisation la relancera.
        //
        // Le message dit CE QU'IL FAUT FAIRE. Un « refusée par le serveur
        // (inconnu) » laissait le gérant devant un voyant rouge permanent, sans
        // la moindre indication sur la marche à suivre.
        await _opQueue.bloquer(
            id,
            'Le serveur ne connaît pas encore « ${_libelleParDefaut(type)} ». '
            'Mettez le serveur à jour, puis touchez « Reprendre ».');
        return false;

      default:
        await _opQueue.markFailed(
            id, 'Opération refusée par le serveur ($statut)');
        return false;
    }
  }

  OpQueueData? _retrouver(List<OpQueueData> ops, String id) {
    for (final op in ops) {
      if (op.id == id) return op;
    }
    return null;
  }

  String _libelleParDefaut(String type) => switch (type) {
        'vente' => 'Vente',
        'vente_modification' => 'Modification de vente',
        'client' => 'Client',
        'article' => 'Article',
        'fournisseur' => 'Fournisseur',
        'fournisseur_delete' => 'Suppression de fournisseur',
        'mouvement' => 'Mouvement de stock',
        'facture_paiement' => 'Versement sur facture',
        'depense' => 'Dépense',
        'depense_reglement' => 'Règlement de dépense',
        'entreprise' => 'Fiche entreprise',
        _ => type,
      };

  /// Réintègre localement la réponse du serveur à une opération poussée.
  ///
  /// [result] est le champ « result » renvoyé par /data/sync ; sa forme dépend
  /// du type d'opération (voir supabase/functions/server).
  Future<void> _fusionnerDepuisServeur(String type, dynamic result) async {
    if (result is! Map) return;
    final r = Map<String, dynamic>.from(result);

    switch (type) {
      case 'vente':
      case 'vente_modification':
        // Réponse : { vente, facture, mouvements, articles }. Les numéros
        // VTE/FAC sont attribués par le serveur : sans cette fusion, la vente et
        // sa facture resteraient sans numéro dans l'application.
        //
        // Pour une modification, le serveur renvoie en plus les articles dont
        // le stock a bougé. C'est SON calcul qui fait foi : il a recalculé les
        // écarts d'après la vente enregistrée, quand le téléphone les avait
        // calculés d'après la copie qu'il avait sous la main.
        final vente = r['vente'];
        if (vente != null) await _stores.upsert('vente', Vente.fromJson(vente));
        final facture = r['facture'];
        if (facture != null) {
          await _stores.upsert('facture', Facture.fromJson(facture));
        }
        for (final m in (r['mouvements'] as List? ?? const [])) {
          await _stores.upsert('mouvement', MouvementStock.fromJson(m));
        }
        for (final a in (r['articles'] as List? ?? const [])) {
          await _stores.upsert('article', Article.fromJson(a));
        }

      case 'client':
        final record = r['record'];
        if (record != null) {
          await _stores.upsert('client', Client.fromJson(record));
        }

      case 'article':
        final record = r['record'];
        if (record != null) {
          await _stores.upsert('article', Article.fromJson(record));
        }

      case 'fournisseur':
        final record = r['record'];
        if (record != null) {
          await _stores.upsert('fournisseur', Fournisseur.fromJson(record));
        }

      case 'fournisseur_delete':
        // Rien à réintégrer : la suppression locale a déjà eu lieu.
        break;

      case 'mouvement':
        // Réponse : { mouvement, article }. Le stock du serveur fait foi.
        final mouvement = r['mouvement'];
        if (mouvement != null) {
          await _stores.upsert('mouvement', MouvementStock.fromJson(mouvement));
        }
        final article = r['article'];
        if (article != null) {
          await _stores.upsert('article', Article.fromJson(article));
        }

      case 'facture_paiement':
        // Réponse : { record } — la facture recalculée (statut, paiements).
        final record = r['record'];
        if (record != null) {
          await _stores.upsert('facture', Facture.fromJson(record));
        }

      case 'depense':
      case 'depense_reglement':
        // Réponse : { record } — la dépense recalculée (numéro, statut).
        final record = r['record'];
        if (record != null) {
          await _stores.upsert('depense', Depense.fromJson(record));
        }

      case 'entreprise':
        final record = r['record'] ?? r['entreprise'];
        if (record != null) {
          await _stores.upsert('entreprise', Entreprise.fromJson(record));
        }
    }
  }

  // ── Récupération ───────────────────────────────────────────────────────────

  Future<void> _tirerSiNecessaire({bool forcer = false}) async {
    final versionLocale = await _stores.getDataVersion();
    final reponse = await _apiClient.dio.get(kDataVersion);
    final versionServeur = (reponse.data['version'] as num?)?.toInt();
    if (versionServeur == null) return;
    if (!forcer && versionServeur == versionLocale) return;

    final tout = await _apiClient.dio.get(kDataAll);
    final donnees = tout.data as Map<String, dynamic>;

    await _appliquerInstantane(donnees);
    await _stores.setDataVersion(
        (donnees['version'] as num?)?.toInt() ?? versionServeur);

    // Ce que le magasin a saisi et qui n'est pas encore parti ne doit pas
    // disparaître de l'écran sous l'effet de l'instantané du serveur.
    await _rejouerOperationsLocales();
  }

  Future<void> _appliquerInstantane(Map<String, dynamic> donnees) async {
    await _stores.appliquerInstantane({
      'article': _parser(donnees['articles'], Article.fromJson),
      'vente': _parser(donnees['ventes'], Vente.fromJson),
      'facture': _parser(donnees['factures'], Facture.fromJson),
      'client': _parser(donnees['clients'], Client.fromJson),
      'depense': _parser(donnees['depenses'], Depense.fromJson),
      'mouvement': _parser(donnees['mouvements'], MouvementStock.fromJson),
      // Absente de l'instantané, la clé n'est PAS traitée comme une liste vide :
      // `appliquerInstantane` supprime tout ce que le serveur ne renvoie plus,
      // et un serveur pas encore déployé effacerait alors les fournisseurs
      // saisis sur le téléphone à chaque synchronisation.
      if (donnees['fournisseurs'] != null)
        'fournisseur': _parser(donnees['fournisseurs'], Fournisseur.fromJson),
      // Le serveur nomme cette clé « utilisateurs » (et non « users »).
      if (donnees['utilisateurs'] != null)
        'user': _parser(donnees['utilisateurs'], Utilisateur.fromJson),
    });

    // Les droits du compte connecté suivent le même instantané : un droit
    // accordé ou retiré depuis l'application web s'applique au prochain
    // battement, sans que personne n'ait à fermer l'application.
    final rappel = onUtilisateurs;
    if (rappel != null && donnees['utilisateurs'] != null) {
      await rappel(
          _parser(donnees['utilisateurs'], Utilisateur.fromJson)
              .cast<Utilisateur>());
    }

    // La fiche du serveur fait foi, y compris quand elle est VIDE.
    //
    // La version précédente conservait le logo et la signature locaux dès que
    // le serveur en renvoyait des vides. L'intention était bonne — ne pas
    // perdre une image — mais elle rendait leur SUPPRESSION impossible :
    // retirer le logo depuis l'application web ne l'effaçait jamais du
    // téléphone, qui continuait à l'imprimer sur les factures. Or `/data/all`
    // renvoie la fiche entière, images comprises : un champ vide y signifie
    // « vidé », pas « non transmis ».
    //
    // Les autres champs de la fiche locale sont conservés en dessous, pour un
    // serveur plus ancien qui n'en connaîtrait pas encore certains.
    if (donnees['entreprise'] != null) {
      final entRes = donnees['entreprise'] as Map<String, dynamic>;
      final existante = await _stores.getEntreprise();
      await _stores.upsert(
        'entreprise',
        Entreprise.fromJson({
          ...(existante?.toJson() ?? const <String, dynamic>{}),
          ...entRes,
        }),
      );
    }

    // Le journal part en dernier : une notification est un agrément, elle ne
    // doit jamais empêcher les données de s'écrire. On l'isole donc du reste du
    // cycle, quitte à perdre une bannière.
    final versActivites = onActivites;
    if (versActivites != null && donnees['activites'] is List) {
      try {
        await versActivites((donnees['activites'] as List)
            .whereType<Map<String, dynamic>>()
            .map(ActiviteEntree.fromJson)
            .toList());
      } catch (e) {
        debugPrint('Journal d\'activité non transmis aux notifications : $e');
      }
    }
  }

  List<dynamic> _parser(dynamic data, Function fromJson) {
    if (data is! List) return const [];
    return data.map((e) => fromJson(e)).toList();
  }

  Future<void> _rejouerOperationsLocales() async {
    for (final op in await _opQueue.getAllOperations()) {
      try {
        await _appliquerLocalement(
            op.type, jsonDecode(op.payloadJson) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Erreur de réapplication locale ${op.id} : $e');
      }
    }
  }

  Future<void> _appliquerLocalement(
      String type, Map<String, dynamic> payload) async {
    switch (type) {
      case 'vente':
        final venteData = payload['vente'];
        if (venteData == null) return;
        final vente = Vente.fromJson(venteData);
        // Si la vente est déjà revenue du serveur, son effet sur le stock y est
        // déjà pris en compte : ne rien rejouer, sous peine de décrémenter deux
        // fois.
        if (await _stores.getVente(vente.id) != null) return;

        await _stores.upsert('vente', vente);

        final factureData = payload['facture'];
        if (factureData != null) {
          final facture = Facture.fromJson(factureData);
          if (await _stores.getFacture(facture.id) == null) {
            await _stores.upsert('facture', facture);
          }
        }

        for (final ligne in (payload['lignesStock'] as List? ?? const [])) {
          final article = await _stores.getArticle(ligne['articleId']);
          if (article == null) continue;
          await _stores.upsert('article',
              article.copyWith(stock: article.stock - (ligne['quantite'] as int)));
        }

      case 'vente_modification':
        // La modification n'est pas encore partie : elle doit primer sur la
        // vente tout juste récupérée du serveur, qui porte encore les anciennes
        // lignes. Sans ce rejeu, l'écran « oubliait » la correction dès le
        // premier instantané suivant, sous les yeux de l'utilisateur.
        //
        // Le stock, lui, n'est PAS retouché ici : il l'a été au moment de la
        // saisie, et l'instantané du serveur ne connaît pas encore la
        // modification. Le recalculer reviendrait à appliquer deux fois le même
        // écart.
        final venteId = payload['venteId'] as String?;
        if (venteId == null) return;
        final existante = await _stores.getVente(venteId);
        if (existante == null) return;

        final lignes = (payload['lignes'] as List? ?? const [])
            .map((l) => LigneVente.fromJson(l as Map<String, dynamic>))
            .toList();
        if (lignes.isEmpty) return;
        final total = lignes.fold<int>(0, (s, l) => s + l.total);

        // Déjà appliquée côté serveur : ses lignes correspondent déjà à ce
        // qu'on voulait, il n'y a rien à rejouer.
        if (existante.totalNet == total &&
            existante.lignes.length == lignes.length) {
          return;
        }

        await _stores.upsert(
          'vente',
          existante.copyWith(
            clientId: payload['clientId'] as String? ?? existante.clientId,
            lignes: lignes,
            totalHT: total,
            totalNet: total,
          ),
        );

        final factureId = payload['factureId'] as String?;
        if (factureId != null) {
          final facture = await _stores.getFacture(factureId);
          if (facture != null) {
            await _stores.upsert('facture',
                facture.copyWith(montantHT: total, montantTTC: total));
          }
        }

      case 'client':
        final record = Client.fromJson(payload['record']);
        // La modification locale n'est pas encore poussée : elle doit primer
        // sur la version tout juste récupérée du serveur, sinon elle
        // disparaîtrait de l'écran. On conserve le `rev` serveur pour que la
        // prochaine édition envoie un `baseRev` à jour.
        final serveur = await _stores.getClient(record.id);
        await _stores.upsert('client', record.copyWith(rev: serveur?.rev));

      case 'article':
        final record = Article.fromJson(payload['record']);
        final serveur = await _stores.getArticle(record.id);
        await _stores.upsert('article', record.copyWith(rev: serveur?.rev));

      case 'fournisseur':
        final record = Fournisseur.fromJson(payload['record']);
        final serveur = await _stores.getFournisseur(record.id);
        await _stores.upsert('fournisseur', record.copyWith(rev: serveur?.rev));

      case 'fournisseur_delete':
        await _stores.supprimer('fournisseur', payload['id'] as String);

      case 'mouvement':
        final mouvement = MouvementStock.fromJson(payload['mouvement']);
        // Déjà revenu du serveur : son effet sur le stock y est compris, le
        // rejouer décrémenterait deux fois. Même garde que pour une vente.
        if (await _stores.getMouvement(mouvement.id) != null) return;

        await _stores.upsert('mouvement', mouvement);

        // Et le stock avec lui. Sans cette ligne, une entrée de marchandise
        // saisie hors ligne laissait le stock inchangé à l'écran : le magasin
        // voyait toujours zéro barre après en avoir reçu cinquante, les
        // ressaisissait, et le serveur en comptait cent au retour du réseau.
        final articleMv = await _stores.getArticle(mouvement.articleId);
        if (articleMv == null) return;
        await _stores.upsert(
          'article',
          articleMv.copyWith(
            stock: stockApresMouvement(
                articleMv.stock, mouvement.type, mouvement.quantite),
          ),
        );

      case 'facture_paiement':
        final paiement = Paiement.fromJson(payload['paiement']);
        final facture = await _stores.getFacture(payload['factureId']);
        if (facture != null &&
            !facture.paiements.any((p) => p.id == paiement.id)) {
          await _stores.upsert('facture', facture.avecPaiement(paiement));
        }

      case 'depense':
        final record = Depense.fromJson(payload['record']);
        final serveur = await _stores.getDepense(record.id);
        await _stores.upsert('depense', record.copyWith(rev: serveur?.rev));

      case 'depense_reglement':
        final reglement = Reglement.fromJson(payload['reglement']);
        final depense = await _stores.getDepense(payload['depenseId']);
        if (depense != null &&
            !depense.reglements.any((r) => r.id == reglement.id)) {
          await _stores.upsert('depense', depense.avecReglement(reglement));
        }

      case 'entreprise':
        final record = payload['record'] ?? payload['entreprise'];
        if (record != null) {
          final serveur = await _stores.getEntreprise();
          final ent = Entreprise.fromJson(record);
          final mergedRecord = {
            ...ent.toJson(),
            if (serveur?.rev != null) '_rev': serveur!.rev,
            if (serveur?.updatedAt != null) '_updatedAt': serveur!.updatedAt,
            if (serveur?.updatedBy != null) '_updatedBy': serveur!.updatedBy,
          };
          await _stores.upsert('entreprise', Entreprise.fromJson(mergedRecord));
        }
    }
  }

  // --- Points d'entrée réservés aux tests ---
  // Les étapes du cycle sont privées ; ces adaptateurs permettent de les
  // vérifier unitairement sans exposer l'implémentation.

  /// [conflits] recueille les conflits détectés ; omis, ils sont ignorés.
  @visibleForTesting
  Future<bool> debugTraiterResultat(
          List<OpQueueData> paquet, Map<String, dynamic> resultat,
          [List<ConflitsCompanion>? conflits]) =>
      _traiterResultat(paquet, resultat, conflits ?? []);

  @visibleForTesting
  Future<void> debugAppliquerInstantane(Map<String, dynamic> donnees) =>
      _appliquerInstantane(donnees);

  @visibleForTesting
  Future<void> debugRejouerOperationsLocales() => _rejouerOperationsLocales();
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final moteur = SyncEngine(
    apiClient: ref.watch(apiClientProvider),
    stores: ref.watch(storesProvider),
    opQueue: ref.watch(opQueueProvider),
    conflits: ref.watch(registreConflitsProvider),
    syncState: ref.watch(syncStateProvider.notifier),
    connectivity: Connectivity(),
    onUtilisateurs: (utilisateurs) =>
        ref.read(authStateProvider.notifier).appliquerUtilisateurs(utilisateurs),
    onActivites: (journal) =>
        ref.read(notificationsProvider.notifier).ingerer(journal),
  );
  // Sans cela, un rechargement du provider laisserait derrière lui un moteur
  // dont les abonnements et les minuteurs continuent de tourner.
  ref.onDispose(moteur.stop);
  return moteur;
});
