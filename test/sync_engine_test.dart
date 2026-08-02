import 'dart:convert';

import 'package:eas_sarlu/core/db/app_database.dart' hide OpQueue;
import 'package:eas_sarlu/core/db/stores.dart';
import 'package:eas_sarlu/core/sync/op_queue.dart';
import 'package:eas_sarlu/core/sync/sync_engine.dart';
import 'package:eas_sarlu/core/sync/sync_state.dart';
import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage sécurisé en mémoire : les signatures doivent reprendre
/// l'intégralité des paramètres nommés de [FlutterSecureStorage].
class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _storage[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage[key] = value ?? '';
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }
}

void main() {
  late AppDatabase db;
  late Stores stores;
  late OpQueue opQueue;
  late RegistreConflits registreConflits;
  late SyncStateNotifier syncStateNotifier;

  /// Moteur branché sur la base en mémoire. Aucun test ci-dessous ne déclenche
  /// d'appel réseau : seules les étapes locales du cycle sont vérifiées.
  SyncEngine creerMoteur() => SyncEngine(
        apiClient: ApiClient(secureStorage: FakeFlutterSecureStorage()),
        stores: stores,
        opQueue: opQueue,
        conflits: registreConflits,
        syncState: syncStateNotifier,
        connectivity: Connectivity(),
      );

  setUp(() async {
    db = AppDatabase.inMemory();
    stores = Stores(db);
    opQueue = OpQueue(db);
    registreConflits = RegistreConflits(db);
    syncStateNotifier = SyncStateNotifier(opQueue.watchPendingCount());
  });

  tearDown(() async {
    await db.close();
  });

  test('deja_applique ne réapplique pas et supprime l\'opération', () async {
    final engine = creerMoteur();

    final payload = {
      'record': {'id': 'c1', 'nom': 'Test Client'}
    };
    final opId = await opQueue.enqueue('client', payload);

    final result = {
      'id': opId,
      'type': 'client',
      'statut': 'deja_applique',
    };

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, result);

    final remaining = await opQueue.getPendingOperations();
    expect(remaining.length, 0);

    final client = await stores.getClient('c1');
    expect(client, isNull);
  });

  test('une opération en conflit SORT de la file et part au registre',
      () async {
    // Le comportement précédent la laissait dans la file. Elle repartait donc
    // à chaque cycle pour reproduire le même conflit, et bloquait derrière elle
    // toutes les ventes suivantes : la synchronisation ne repassait plus jamais.
    // C'est la règle de l'application web (`partitionnerFile`) : le conflit
    // sort de la file et attend un arbitrage, sans que rien ne soit jeté.
    final engine = creerMoteur();

    final opId = await opQueue.enqueue('client', {
      'record': {'id': 'c1', 'nom': 'Client Local'},
      'baseRev': 1,
    }, libelle: 'Client Mamadou Barry');

    final conflits = <ConflitsCompanion>[];
    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opId,
      'type': 'client',
      'statut': 'conflit',
      'current': {'id': 'c1', 'nom': 'Client Serveur', '_rev': 2},
      'tentative': {'id': 'c1', 'nom': 'Client Local'},
    }, conflits);

    expect(await opQueue.getPendingOperations(), isEmpty,
        reason: 'le conflit ne doit plus bloquer la file');

    expect(conflits, hasLength(1));
    await registreConflits.ajouter(conflits);

    final enregistres = await registreConflits.tous();
    expect(enregistres, hasLength(1));
    expect(enregistres.first.id, opId);
    expect(enregistres.first.libelle, 'Client Mamadou Barry');
    expect(jsonDecode(enregistres.first.serveurJson)['nom'], 'Client Serveur');

    // La tentative conservée est la charge utile LOCALE complète, enveloppe
    // comprise : c'est elle, et elle seule, qui peut être remise dans la file
    // si l'utilisateur choisit de garder sa version.
    final tentative =
        jsonDecode(enregistres.first.tentativeJson) as Map<String, dynamic>;
    expect(tentative['record']['nom'], 'Client Local');
    expect(tentative['baseRev'], 1);
  });

  test('une opération en conflit ne bloque pas celles qui la suivent',
      () async {
    final engine = creerMoteur();

    final opConflit = await opQueue.enqueue('client', {
      'record': {'id': 'c1', 'nom': 'Client Local'},
    });
    final opSuivante = await opQueue.enqueue('article', {
      'record': {'id': 'a1', 'nom': 'Tube', 'unite': 'Barre'},
    });

    final conflits = <ConflitsCompanion>[];
    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opConflit,
      'type': 'client',
      'statut': 'conflit',
      'current': {'id': 'c1', 'nom': 'Client Serveur', '_rev': 2},
    }, conflits);

    final restantes = await opQueue.getPendingOperations();
    expect(restantes, hasLength(1));
    expect(restantes.first.id, opSuivante,
        reason: 'l\'article doit rester prêt à partir');
  });

  test('le pull n\'écrase pas une opération en file (réapplication)', () async {
    final clientServeur = Client(id: 'c1', nom: 'Client Serveur');
    await stores.upsert('client', clientServeur);

    final payload = {
      'record': {'id': 'c1', 'nom': 'Client Local Modifié'},
    };
    await opQueue.enqueue('client', payload);

    final engine = creerMoteur();

    final pullData = {
      'articles': [],
      'ventes': [],
      'factures': [],
      'clients': [
        {'id': 'c1', 'nom': 'Client Serveur Nouveau'}
      ],
      'depenses': [],
      'mouvements': [],
      'users': [],
    };

    await engine.debugAppliquerInstantane(pullData);
    await engine.debugRejouerOperationsLocales();

    final clientFinal = await stores.getClient('c1');
    expect(clientFinal, isNotNull);
    expect(clientFinal!.nom, 'Client Local Modifié');

    final ops = await opQueue.getPendingOperations();
    expect(ops.length, 1);
  });

  test('UUID d\'une opération survit à un échec réseau', () async {
    final payload = {
      'record': {'id': 'a1', 'nom': 'Article'}
    };
    final opId = await opQueue.enqueue('article', payload);

    await opQueue.markFailed(opId, 'Erreur réseau');

    // L'opération reste en base — un échec réseau est transitoire — mais elle
    // n'est plus « prête à partir » : elle attend avant de réessayer, sans quoi
    // elle repartirait à chaque cycle et saturerait la file.
    final toutes = await opQueue.getAllOperations();
    expect(toutes.length, 1);
    expect(toutes.first.id, opId);
    expect(toutes.first.tentatives, 1);
    expect(toutes.first.dernierErreur, 'Erreur réseau');
    expect(toutes.first.prochainEssai, isNotNull);
    expect(toutes.first.bloquee, isFalse);

    expect(await opQueue.getPendingOperations(), isEmpty,
        reason: 'elle doit patienter avant de repartir');
  });

  test('une opération qui échoue sans cesse finit par s\'arrêter', () async {
    final opId = await opQueue.enqueue('mouvement', {
      'mouvement': {'id': 'm1', 'articleId': 'introuvable'},
    });

    // Sans plafond, une opération que le serveur refuse toujours repartait
    // indéfiniment et emportait dans la même requête toutes les ventes
    // légitimes de la file.
    for (var i = 0; i < kMaxTentatives; i++) {
      await opQueue.markFailed(opId, 'Article introuvable');
    }

    final toutes = await opQueue.getAllOperations();
    expect(toutes.first.bloquee, isTrue);
    expect(toutes.first.tentatives, kMaxTentatives);
    expect(await opQueue.getPendingOperations(), isEmpty);

    // Rien n'est perdu : l'utilisateur peut la relancer.
    await opQueue.reprendre(opId);
    expect(await opQueue.getPendingOperations(), hasLength(1));
  });
  // ─── Contrat avec le serveur (supabase/functions/server) ────────────────────
  // Le serveur répond { statut, result, erreur } — pas { data, error } — et la
  // forme de « result » dépend du type. Ces tests figent ce contrat.

  test('une vente appliquée récupère les numéros attribués par le serveur',
      () async {
    final engine = creerMoteur();
    final opId = await opQueue.enqueue('vente', {
      'vente': {'id': 'v1', 'clientId': 'c1', 'date': '2026-07-29T10:00:00Z'},
      'facture': {'id': 'f1', 'venteId': 'v1', 'clientId': 'c1'},
      'lignesStock': [],
    });

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opId,
      'type': 'vente',
      'statut': 'applique',
      'result': {
        'ok': true,
        'vente': {
          'id': 'v1',
          'numero': 'VTE-2026-0001',
          'clientId': 'c1',
          'date': '2026-07-29T10:00:00Z',
          '_rev': 1,
        },
        'facture': {
          'id': 'f1',
          'numero': 'FAC-2026-0001',
          'venteId': 'v1',
          'clientId': 'c1',
          'dateEmission': '2026-07-29T10:00:00Z',
          '_rev': 1,
        },
        'mouvements': [
          {
            'id': 'MV1',
            'articleId': 'a1',
            'type': 'sortie',
            'quantite': 2,
            'date': '2026-07-29T10:00:00Z',
          }
        ],
      },
    });

    expect((await stores.getVente('v1'))?.numero, 'VTE-2026-0001');
    expect((await stores.getFacture('f1'))?.numero, 'FAC-2026-0001');
    expect((await stores.watchMouvements().first).length, 1);
    expect((await opQueue.getPendingOperations()), isEmpty);
  });

  test('un article appliqué récupère le _rev du serveur', () async {
    final engine = creerMoteur();
    final opId = await opQueue.enqueue('article', {
      'record': {'id': 'a1', 'nom': 'Tube', 'unite': 'Barre'},
    });

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opId,
      'type': 'article',
      'statut': 'applique',
      'result': {
        'record': {'id': 'a1', 'nom': 'Tube', 'unite': 'Barre', '_rev': 7},
      },
    });

    // Sans ce _rev, la prochaine modification enverrait un baseRev périmé et
    // le serveur répondrait « conflit » indéfiniment.
    expect((await stores.getArticle('a1'))?.rev, 7);
  });

  test('un mouvement appliqué aligne le stock sur celui du serveur', () async {
    await stores.upsert('article',
        Article(id: 'a1', nom: 'Tube', unite: 'Barre', stock: 50, rev: 1));
    final engine = creerMoteur();
    final opId = await opQueue.enqueue('mouvement', {
      'mouvement': {
        'id': 'm1',
        'articleId': 'a1',
        'type': 'sortie',
        'quantite': 5,
        'date': '2026-07-29T10:00:00Z',
      },
    });

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opId,
      'type': 'mouvement',
      'statut': 'applique',
      'result': {
        'mouvement': {
          'id': 'm1',
          'articleId': 'a1',
          'type': 'sortie',
          'quantite': 5,
          'quantiteAvant': 50,
          'quantiteApres': 45,
          'date': '2026-07-29T10:00:00Z',
        },
        'article': {
          'id': 'a1',
          'nom': 'Tube',
          'unite': 'Barre',
          'stock': 45,
          '_rev': 2,
        },
      },
    });

    final article = await stores.getArticle('a1');
    expect(article?.stock, 45);
    expect(article?.rev, 2);
  });

  test('un versement appliqué remplace la facture par celle du serveur',
      () async {
    final engine = creerMoteur();
    final opId = await opQueue.enqueue('facture_paiement', {
      'factureId': 'f1',
      'paiement': {'id': 'p1', 'date': '2026-07-29', 'montant': 100},
    });

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opId,
      'type': 'facture_paiement',
      'statut': 'applique',
      'result': {
        'record': {
          'id': 'f1',
          'numero': 'FAC-2026-0001',
          'venteId': 'v1',
          'clientId': 'c1',
          'dateEmission': '2026-07-29',
          'montantTTC': 100,
          'statut': 'payée',
          'paiements': [
            {'id': 'p1', 'date': '2026-07-29', 'montant': 100}
          ],
          '_rev': 3,
        },
      },
    });

    final facture = await stores.getFacture('f1');
    expect(facture?.statut, 'payée');
    expect(facture?.paiements.length, 1);
    expect(facture?.rev, 3);
  });

  test('un echec relaie le message du serveur (champ « erreur »)', () async {
    final engine = creerMoteur();
    final opId = await opQueue.enqueue('depense', {
      'record': {'id': 'd1', 'date': '2026-07-29', 'montant': 0},
    });

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opId,
      'type': 'depense',
      'statut': 'echec',
      'erreur': 'Dépense incomplète',
    });

    final restantes = await opQueue.getAllOperations();
    expect(restantes.first.dernierErreur, 'Dépense incomplète');
  });

  test('un statut inconnu ne boucle pas indéfiniment', () async {
    final engine = creerMoteur();
    final opId = await opQueue.enqueue('type_bidon', {'record': {}});

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(
        ops, {'id': opId, 'type': 'type_bidon', 'statut': 'inconnu'});

    final restantes = await opQueue.getAllOperations();
    expect(restantes.first.tentatives, 1);
    expect(restantes.first.dernierErreur, contains('refusée'));
  });

  test('le pull charge les utilisateurs depuis la clé « utilisateurs »',
      () async {
    final engine = creerMoteur();
    await engine.debugAppliquerInstantane({
      'articles': [],
      'ventes': [],
      'factures': [],
      'clients': [],
      'depenses': [],
      'mouvements': [],
      'utilisateurs': [
        {'id': 'u1', 'nom': 'Patron', 'email': 'p@eas.gn'}
      ],
    });

    final users = await stores.watchUtilisateurs().first;
    expect(users.length, 1);
    expect(users.first.nom, 'Patron');
  });


  // ─── Instantané du serveur ──────────────────────────────────────────────────

  test('l\'instantané n\'écrit que ce qui a changé', () async {
    // Le pull effaçait puis réinsérait toutes les lignes de chaque type à
    // chaque synchronisation : deux écritures par enregistrement, répétées à
    // chaque vente sur tout le catalogue. C'est de là que venaient les
    // à-coups. Une synchronisation qui n'apporte rien ne doit rien écrire.
    final engine = creerMoteur();
    final instantane = {
      'articles': [
        {'id': 'a1', 'nom': 'Tube', 'unite': 'Barre', 'stock': 10, '_rev': 1},
        {'id': 'a2', 'nom': 'Tôle', 'unite': 'Feuille', 'stock': 5, '_rev': 1},
      ],
      'ventes': [], 'factures': [], 'clients': [], 'depenses': [],
      'mouvements': [],
    };

    await engine.debugAppliquerInstantane(instantane);
    expect((await stores.getArticles()).length, 2);

    var ecritures = 0;
    final abonnement = stores.watchArticles().listen((_) => ecritures++);
    await Future<void>.delayed(Duration.zero);
    ecritures = 0;

    // Le même instantané, une seconde fois.
    await engine.debugAppliquerInstantane(instantane);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ecritures, 0, reason: 'rien n\'a changé, rien ne doit être réécrit');

    await abonnement.cancel();
  });

  test('l\'instantané supprime ce que le serveur ne renvoie plus', () async {
    final engine = creerMoteur();
    await stores.upsert('article',
        Article(id: 'obsolete', nom: 'Supprimé ailleurs', unite: 'Barre'));

    await engine.debugAppliquerInstantane({
      'articles': [
        {'id': 'a1', 'nom': 'Tube', 'unite': 'Barre', '_rev': 1},
      ],
      'ventes': [], 'factures': [], 'clients': [], 'depenses': [],
      'mouvements': [],
    });

    expect(await stores.getArticle('obsolete'), isNull);
    expect(await stores.getArticle('a1'), isNotNull);
  });

  test('l\'instantané met à jour une ligne dont la révision a bougé', () async {
    final engine = creerMoteur();
    await stores.upsert('article',
        Article(id: 'a1', nom: 'Tube', unite: 'Barre', stock: 10, rev: 1));

    await engine.debugAppliquerInstantane({
      'articles': [
        {'id': 'a1', 'nom': 'Tube', 'unite': 'Barre', 'stock': 42, '_rev': 2},
      ],
      'ventes': [], 'factures': [], 'clients': [], 'depenses': [],
      'mouvements': [],
    });

    final article = await stores.getArticle('a1');
    expect(article?.stock, 42);
    expect(article?.rev, 2);
  });

  // ─── Fiche entreprise ───────────────────────────────────────────────────────
  // Les deux applications partagent une seule fiche : ce qui est modifié depuis
  // le navigateur doit atteindre le téléphone, et réciproquement.

  test('une modification de la fiche entreprise atteint le téléphone', () async {
    final engine = creerMoteur();
    await stores.upsert('entreprise',
        Entreprise(nom: 'E.A.S', telephone: '620', ville: 'Conakry', rev: 1));

    await engine.debugAppliquerInstantane({
      'articles': [], 'ventes': [], 'factures': [], 'clients': [],
      'depenses': [], 'mouvements': [],
      'entreprise': {
        'nom': 'E.A.S Sarlu',
        'telephone': '628 00 00 00',
        'ville': 'Conakry',
        '_rev': 2,
      },
    });

    final ent = await stores.getEntreprise();
    expect(ent?.nom, 'E.A.S Sarlu');
    expect(ent?.telephone, '628 00 00 00');
  });

  test('retirer le logo depuis le web le retire aussi du téléphone', () async {
    // Le moteur conservait le logo local dès que le serveur en renvoyait un
    // vide : le supprimer depuis l'application web ne l'effaçait donc jamais du
    // téléphone, qui continuait à l'imprimer sur les factures. `/data/all`
    // renvoie la fiche entière : un champ vide y signifie « vidé ».
    final engine = creerMoteur();
    await stores.upsert(
        'entreprise',
        Entreprise(
          nom: 'E.A.S Sarlu',
          logo: 'data:image/png;base64,AAAA',
          signatureImage: 'data:image/png;base64,BBBB',
          rev: 1,
        ));

    await engine.debugAppliquerInstantane({
      'articles': [], 'ventes': [], 'factures': [], 'clients': [],
      'depenses': [], 'mouvements': [],
      'entreprise': {
        'nom': 'E.A.S Sarlu',
        'logo': '',
        'signatureImage': '',
        '_rev': 2,
      },
    });

    final ent = await stores.getEntreprise();
    expect(ent?.logo, isEmpty);
    expect(ent?.signatureImage, isEmpty);
  });

  // ─── Modification d'une vente ───────────────────────────────────────────────
  // Ces opérations partaient auparavant sous le type « vente », c'est-à-dire par
  // la route de CRÉATION du serveur : un nouveau numéro était alloué, le stock
  // redéduit une seconde fois, et la mise à jour rejetée en silence. Elles ont
  // désormais leur propre type, et le moteur doit le traiter partout.

  Vente venteDeDepart() => Vente(
        id: 'v1',
        numero: 'VTE-2026-0001',
        date: '2026-08-01T10:00:00.000Z',
        clientId: 'c1',
        lignes: [
          LigneVente(
            articleId: 'a1',
            articleRef: 'FER8',
            articleNom: 'Fer à béton 8',
            unite: 'Barre',
            qte: 10,
            prixUnitaire: 50000,
            total: 500000,
          ),
        ],
        totalHT: 500000,
        totalNet: 500000,
        rev: 3,
      );

  test('la réponse du serveur remplace la vente, la facture et les stocks',
      () async {
    final engine = creerMoteur();
    await stores.upsert('vente', venteDeDepart());
    await stores.upsert('article',
        Article(id: 'a1', nom: 'Fer à béton 8', unite: 'Barre', stock: 0));

    final opId = await opQueue.enqueue('vente_modification', {
      'venteId': 'v1',
      'lignes': const <dynamic>[],
      'clientId': 'c1',
    });

    final ops = await opQueue.getPendingOperations();
    await engine.debugTraiterResultat(ops, {
      'id': opId,
      'type': 'vente_modification',
      'statut': 'applique',
      'result': {
        'ok': true,
        'vente': {
          'id': 'v1',
          'numero': 'VTE-2026-0001',
          'date': '2026-08-01T10:00:00.000Z',
          'clientId': 'c1',
          'lignes': [
            {
              'articleId': 'a1',
              'articleRef': 'FER8',
              'articleNom': 'Fer à béton 8',
              'unite': 'Barre',
              'qte': 6,
              'prixUnitaire': 50000,
              'total': 300000,
            }
          ],
          'totalHT': 300000,
          'totalNet': 300000,
          '_rev': 4,
        },
        'facture': {
          'id': 'f1',
          'numero': 'FAC-2026-0001',
          'venteId': 'v1',
          'clientId': 'c1',
          'dateEmission': '2026-08-01T10:00:00.000Z',
          'montantHT': 300000,
          'montantTTC': 300000,
          'paiements': [],
        },
        // Le numéro de vente est CONSERVÉ, et le stock rendu par le serveur
        // fait foi : c'est lui qui a recalculé l'écart d'après la vente telle
        // qu'elle était enregistrée.
        'articles': [
          {'id': 'a1', 'nom': 'Fer à béton 8', 'unite': 'Barre', 'stock': 4},
        ],
        'mouvements': [
          {
            'id': 'mv1',
            'articleId': 'a1',
            'type': 'entrée',
            'quantite': 4,
            'date': '2026-08-02T09:00:00.000Z',
          }
        ],
      },
    });

    final vente = await stores.getVente('v1');
    expect(vente?.numero, 'VTE-2026-0001',
        reason: 'une modification ne doit jamais rebaptiser la vente');
    expect(vente?.totalNet, 300000);
    expect(vente?.lignes.single.qte, 6);

    expect((await stores.getFacture('f1'))?.montantTTC, 300000);
    expect((await stores.getArticle('a1'))?.stock, 4,
        reason: 'les 4 barres retirées de la vente reviennent en stock');
    expect((await stores.getMouvement('mv1'))?.type, 'entrée');
    expect(await opQueue.getPendingOperations(), isEmpty);
  });

  test('le pull n\'efface pas une modification de vente encore en file',
      () async {
    final engine = creerMoteur();
    await stores.upsert('vente', venteDeDepart());

    await opQueue.enqueue('vente_modification', {
      'venteId': 'v1',
      'clientId': 'c1',
      'lignes': [
        {
          'articleId': 'a1',
          'articleRef': 'FER8',
          'articleNom': 'Fer à béton 8',
          'unite': 'Barre',
          'qte': 6,
          'prixUnitaire': 50000,
          'total': 300000,
        }
      ],
    });

    // Le serveur ne connaît pas encore la modification : son instantané porte
    // toujours les dix barres.
    await engine.debugAppliquerInstantane({
      'articles': [], 'clients': [], 'factures': [], 'depenses': [],
      'mouvements': [],
      'ventes': [
        {
          'id': 'v1',
          'numero': 'VTE-2026-0001',
          'date': '2026-08-01T10:00:00.000Z',
          'clientId': 'c1',
          'lignes': [
            {
              'articleId': 'a1',
              'articleRef': 'FER8',
              'articleNom': 'Fer à béton 8',
              'unite': 'Barre',
              'qte': 10,
              'prixUnitaire': 50000,
              'total': 500000,
            }
          ],
          'totalHT': 500000,
          'totalNet': 500000,
          '_rev': 3,
        }
      ],
    });
    await engine.debugRejouerOperationsLocales();

    final vente = await stores.getVente('v1');
    expect(vente?.totalNet, 300000,
        reason: 'la correction ne doit pas disparaître sous les yeux '
            "de l'utilisateur au premier instantané suivant");
    expect(vente?.lignes.single.qte, 6);
  });
}
