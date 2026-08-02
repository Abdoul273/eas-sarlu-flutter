// lib/features/activite/notifications_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart' show sharedPreferencesProvider;
import '../../core/auth/auth_state.dart';
import '../../core/models/activite.dart';
import '../../core/services/notification_service.dart';

// ─── Ce qui mérite d'être signalé ─────────────────────────────────────────────
// La décision de notifier se prend ici ; l'affichage est dans
// `core/services/notification_service.dart`.
//
// Ce fichier n'interroge PAS le serveur. Il est alimenté par le moteur de
// synchronisation, qui reçoit déjà le journal d'activité dans l'instantané
// `/data/all` — et ne le rapatrie que lorsque la version des données a bougé.
// La première version sondait `/data/activites` toutes les vingt secondes, une
// route qui renvoie jusqu'à deux mille entrées : cent quatre-vingts appels par
// heure, en très grande majorité pour réapprendre ce qu'on savait déjà. Sur un
// forfait de Conakry, cela se compte en mégaoctets par jour.
//
// Quatre règles gouvernent ce qui devient une notification :
//
//   1. Jamais de rattrapage à l'installation. Au premier instantané, on se
//      contente de retenir où en est le journal. Sans cela, la première
//      ouverture faisait pleuvoir des centaines de bannières pour des ventes
//      d'il y a six mois — et l'utilisateur coupait les notifications le jour
//      même.
//   2. Jamais sa propre saisie. Être prévenu de la vente qu'on vient de taper
//      soi-même n'apprend rien, et apprend surtout à ignorer les autres.
//   3. Jamais deux fois la même. Le repère avance sur la date ET les
//      identifiants déjà signalés sont mémorisés : deux activités écrites dans
//      la même milliseconde ne se masquent plus l'une l'autre.
//   4. Jamais plus d'une poignée d'un coup. Au retour d'une journée hors ligne,
//      le journal rattrape tout : on affiche les plus récentes et un résumé
//      pour le reste.

/// Nombre de bannières affichées au maximum pour un même lot. Au-delà, un
/// résumé — le volet de notifications d'Android ne se lit plus passé cinq
/// lignes de la même application.
const int _maxBannieresParLot = 5;

/// Entrées conservées pour le menu du badge. Le journal complet reste sur la
/// page Activité ; ici on ne montre que le dessus de la pile.
const int _maxRecentes = 30;

/// Identifiants déjà signalés que l'on garde en mémoire. Assez large pour
/// couvrir plusieurs lots, assez court pour ne pas croître indéfiniment.
const int _maxIdsMemorises = 300;

const _cleDernierNotifie = 'eas_notif_dernier_notifie';
const _cleDernierLu = 'eas_notif_dernier_lu';

@immutable
class NotificationsState {
  /// Les activités récentes, les plus récentes en premier — celles d'autrui
  /// uniquement.
  final List<ActiviteEntree> recentes;

  /// Parmi elles, celles postérieures au dernier passage sur le journal.
  final List<ActiviteEntree> nonLues;

  /// Repère de lecture, `null` si le journal n'a jamais été consulté.
  final DateTime? dernierLu;

  /// L'utilisateur a refusé les notifications système. L'écran de réglages s'en
  /// sert pour expliquer pourquoi rien n'arrive, plutôt que de laisser croire à
  /// une panne.
  final bool permissionRefusee;

  const NotificationsState({
    this.recentes = const [],
    this.nonLues = const [],
    this.dernierLu,
    this.permissionRefusee = false,
  });

  bool get aDuNonLu => nonLues.isNotEmpty;
  int get nombreNonLues => nonLues.length;

  @override
  bool operator ==(Object other) =>
      other is NotificationsState &&
      listEquals(other.recentes, recentes) &&
      listEquals(other.nonLues, nonLues) &&
      other.dernierLu == dernierLu &&
      other.permissionRefusee == permissionRefusee;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(recentes), Object.hashAll(nonLues), dernierLu, permissionRefusee);
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>((ref) {
  return NotificationsNotifier(
    service: ref.watch(notificationServiceProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    nomUtilisateur: () => ref.read(authStateProvider).value?.user?.nom,
  );
});

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  NotificationsNotifier({
    required NotificationService service,
    required SharedPreferences prefs,
    required String? Function() nomUtilisateur,
  })  : _service = service,
        _prefs = prefs,
        _nomUtilisateur = nomUtilisateur,
        super(const NotificationsState()) {
    _relire();
  }

  final NotificationService _service;
  final SharedPreferences _prefs;
  final String? Function() _nomUtilisateur;

  /// Date de la dernière activité signalée. `null` tant qu'aucun instantané n'a
  /// été reçu : c'est ce `null` qui distingue « première installation » de
  /// « rien de neuf », et donc qui empêche le rattrapage massif.
  DateTime? _dernierNotifie;
  DateTime? _dernierLu;

  final Set<String> _dejaSignalees = <String>{};

  void _relire() {
    final notifie = _prefs.getString(_cleDernierNotifie);
    if (notifie != null) _dernierNotifie = DateTime.tryParse(notifie);
    final lu = _prefs.getString(_cleDernierLu);
    if (lu != null) _dernierLu = DateTime.tryParse(lu);
    if (_dernierLu != null) {
      state = NotificationsState(dernierLu: _dernierLu);
    }
  }

  /// Demande la permission système. Appelée une fois l'utilisateur connecté,
  /// pas au premier écran : une demande de permission avant qu'on ait compris à
  /// quoi sert l'application se refuse par réflexe.
  Future<void> demanderPermission() async {
    final accorde = await _service.demanderPermission();
    if (!mounted) return;
    state = NotificationsState(
      recentes: state.recentes,
      nonLues: state.nonLues,
      dernierLu: state.dernierLu,
      permissionRefusee: !accorde && _service.disponible,
    );
  }

  /// Reçoit le journal tel que le serveur vient de le rendre.
  ///
  /// Appelée par le moteur de synchronisation à chaque instantané. La liste
  /// n'est pas supposée triée : le tri est refait ici, parce qu'un tri implicite
  /// est un tri qu'on finit par perdre.
  Future<void> ingerer(List<ActiviteEntree> journal) async {
    final moi = _nomUtilisateur();

    // Les entrées sans date lisible ne sont pas jetées du journal — la page
    // Activité les montre — mais elles ne peuvent pas être comparées à un
    // repère, donc elles ne déclenchent jamais de notification.
    final datees = journal.where((a) => a.dateTime != null).toList()
      ..sort((a, b) => b.dateTriable.compareTo(a.dateTriable));

    final desAutres = datees.where((a) => !a.estDe(moi)).toList();

    if (datees.isEmpty) {
      _publier(const []);
      return;
    }

    final plusRecente = datees.first.dateTriable;

    // Première réception : on pose le repère sans rien signaler.
    if (_dernierNotifie == null) {
      await _memoriser(_cleDernierNotifie, plusRecente);
      _dernierNotifie = plusRecente;
      // Le repère de lecture suit, pour que le badge ne s'allume pas non plus
      // sur un historique que personne n'a demandé à voir.
      if (_dernierLu == null) {
        await _memoriser(_cleDernierLu, plusRecente);
        _dernierLu = plusRecente;
      }
      _publier(desAutres);
      return;
    }

    final repere = _dernierNotifie!;
    final nouvelles = desAutres
        .where((a) =>
            a.dateTriable.isAfter(repere) && !_dejaSignalees.contains(a.id))
        .toList();

    if (nouvelles.isNotEmpty) {
      // Les plus récentes d'abord dans la liste, mais affichées de la plus
      // ancienne à la plus récente : le volet Android empile, la dernière posée
      // finit donc en haut, à sa place.
      final aAfficher = nouvelles.take(_maxBannieresParLot).toList().reversed;
      for (final activite in aAfficher) {
        await _service.afficher(activite);
      }
      if (nouvelles.length > 1) {
        await _service.afficherResume(nouvelles.length);
      }

      for (final a in nouvelles) {
        _dejaSignalees.add(a.id);
      }
      _elaguerIds();

      if (plusRecente.isAfter(repere)) {
        _dernierNotifie = plusRecente;
        await _memoriser(_cleDernierNotifie, plusRecente);
      }
    } else if (plusRecente.isAfter(repere)) {
      // Rien à signaler (tout venait de nous), mais le repère doit avancer :
      // sinon chaque instantané suivant réexamine les mêmes entrées.
      _dernierNotifie = plusRecente;
      await _memoriser(_cleDernierNotifie, plusRecente);
    }

    _publier(desAutres);
  }

  void _publier(List<ActiviteEntree> desAutres) {
    if (!mounted) return;
    final recentes = desAutres.take(_maxRecentes).toList();
    final lu = _dernierLu;
    final nonLues = lu == null
        ? recentes
        : recentes.where((a) => a.dateTriable.isAfter(lu)).toList();
    state = NotificationsState(
      recentes: recentes,
      nonLues: nonLues,
      dernierLu: lu,
      permissionRefusee: state.permissionRefusee,
    );
  }

  /// Marque tout comme lu.
  ///
  /// Le repère prend la date de l'activité la plus récente CONNUE, et non
  /// l'heure du téléphone : une horloge en avance de quelques minutes — le cas
  /// courant — masquerait sinon les activités arrivées entre-temps, qui ne
  /// reviendraient jamais.
  Future<void> marquerLu() async {
    final repere = state.recentes.isNotEmpty
        ? state.recentes.first.dateTriable
        : DateTime.now();
    _dernierLu = repere;
    await _memoriser(_cleDernierLu, repere);
    await _service.toutEffacer();
    if (!mounted) return;
    state = NotificationsState(
      recentes: state.recentes,
      nonLues: const [],
      dernierLu: repere,
      permissionRefusee: state.permissionRefusee,
    );
  }

  /// Remet le fil à zéro : changement de compte, déconnexion. Les repères
  /// persistés sont effacés, faute de quoi le compte suivant hériterait de
  /// l'historique de lecture du précédent.
  Future<void> reinitialiser() async {
    _dernierNotifie = null;
    _dernierLu = null;
    _dejaSignalees.clear();
    await _prefs.remove(_cleDernierNotifie);
    await _prefs.remove(_cleDernierLu);
    await _service.toutEffacer();
    if (!mounted) return;
    state = const NotificationsState();
  }

  void _elaguerIds() {
    if (_dejaSignalees.length <= _maxIdsMemorises) return;
    final surplus = _dejaSignalees.length - _maxIdsMemorises;
    _dejaSignalees.removeAll(_dejaSignalees.take(surplus).toList());
  }

  Future<void> _memoriser(String cle, DateTime valeur) =>
      _prefs.setString(cle, valeur.toIso8601String());
}
