// lib/core/services/notification_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activite.dart';

// ─── Notifications système ────────────────────────────────────────────────────
// La couche « Android » du système de notifications : elle sait afficher, elle
// ne sait pas quoi afficher. Décider ce qui mérite une notification est le
// travail de `notifications_provider.dart` ; ce fichier-ci ne fait que poser la
// bannière et rapporter le clic.
//
// Trois précautions gouvernent tout ce fichier :
//
//   1. Depuis Android 13, une application qui n'a pas demandé
//      POST_NOTIFICATIONS n'affiche RIEN — sans erreur, sans journal, sans le
//      moindre indice. La permission est donc demandée explicitement, et son
//      refus est un état connu que l'interface peut expliquer.
//   2. Les canaux sont créés à l'avance, avec leur nom et leur description.
//      Créés implicitement au premier `show`, ils apparaissent dans les
//      réglages Android sous un intitulé technique que personne ne peut
//      rattacher à quoi que ce soit.
//   3. Chaque appel au greffon est isolé : sur un poste de test, sur le web ou
//      sur un système sans service de notification, le canal de méthode n'existe
//      pas et lève. Une notification qu'on ne peut pas afficher ne doit jamais
//      faire tomber la synchronisation qui l'a déclenchée.

/// Ce que le clic sur une notification demande d'ouvrir.
class ClicNotification {
  /// Chemin de la page à ouvrir (`/factures/abc`), ou `null` pour le journal.
  final String? destination;
  final String activiteId;

  const ClicNotification({required this.activiteId, this.destination});
}

/// Identifiants des canaux Android. Ils sont figés : renommer une constante
/// crée un NOUVEAU canal côté système et perd les réglages que l'utilisateur y
/// avait faits (son coupé, importance abaissée).
const Map<FamilleActivite, String> _idCanal = {
  FamilleActivite.argent: 'eas_argent',
  FamilleActivite.stock: 'eas_stock',
  FamilleActivite.administration: 'eas_admin',
};

/// Clé de regroupement Android : toutes les notifications de l'application se
/// replient sous une même pile plutôt que d'occuper onze lignes du volet.
const String _cleGroupe = 'eas_sarlu_activites';

/// Identifiant réservé à la notification de résumé du groupe. Choisi hors de la
/// plage des identifiants dérivés d'une activité (voir [_idPour]).
const int _idResume = 1;

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.fermer);
  return service;
});

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? greffon})
      : _greffon = greffon ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _greffon;

  final StreamController<ClicNotification> _clics =
      StreamController<ClicNotification>.broadcast();

  /// Les clics sur une notification, à écouter par la couche de navigation.
  Stream<ClicNotification> get clics => _clics.stream;

  Future<void>? _initialisation;
  bool _disponible = true;
  bool? _autorise;

  /// L'utilisateur a-t-il accordé la permission ? `null` tant qu'on n'a pas
  /// demandé. Sert à l'écran de réglages, qui doit pouvoir dire pourquoi rien
  /// n'arrive.
  bool? get autorise => _autorise;

  /// Le greffon répond-il sur cette plateforme ? Faux sur un poste de test.
  bool get disponible => _disponible;

  /// Initialise le greffon une seule fois, même si plusieurs appels partent en
  /// parallèle : `showNotification` et le démarrage de l'application appelaient
  /// tous deux `init()`, et deux initialisations concurrentes enregistraient
  /// deux fois le gestionnaire de clic.
  Future<void> init() => _initialisation ??= _initialiser();

  Future<void> _initialiser() async {
    try {
      const parametresAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      // Les permissions iOS sont demandées par `demanderPermission()`, pas à
      // l'initialisation : une demande qui surgit au tout premier lancement,
      // avant que l'utilisateur ait vu un seul écran, se refuse par réflexe.
      const parametresIOS = DarwinInitializationSettings(
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestAlertPermission: false,
      );

      await _greffon.initialize(
        const InitializationSettings(
            android: parametresAndroid, iOS: parametresIOS),
        onDidReceiveNotificationResponse: _surReponse,
      );

      await _creerCanaux();

      // L'application a peut-être été LANCÉE depuis une notification : le clic
      // est alors survenu avant que le gestionnaire ci-dessus n'existe. Sans
      // cette relecture, ouvrir l'application depuis la bannière retombait sur
      // l'accueil, comme si l'on n'avait rien touché.
      final lancement = await _greffon.getNotificationAppLaunchDetails();
      if (lancement?.didNotificationLaunchApp ?? false) {
        final reponse = lancement!.notificationResponse;
        if (reponse != null) _surReponse(reponse);
      }
    } catch (e) {
      // Plateforme sans greffon (tests, bureau, web) : on continue sans
      // notifications plutôt que d'empêcher l'application de démarrer.
      _disponible = false;
      debugPrint('Notifications indisponibles sur cette plateforme : $e');
    }
  }

  Future<void> _creerCanaux() async {
    final android = _greffon.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final entree in _idCanal.entries) {
      await android.createNotificationChannel(AndroidNotificationChannel(
        entree.value,
        kLibelleFamille[entree.key]!,
        description: _descriptionCanal(entree.key),
        // L'argent sonne, le reste s'affiche sans bruit : c'est le réglage par
        // défaut, l'utilisateur reste libre de le changer canal par canal dans
        // les réglages Android.
        importance: entree.key == FamilleActivite.argent
            ? Importance.high
            : Importance.defaultImportance,
      ));
    }
  }

  String _descriptionCanal(FamilleActivite famille) {
    switch (famille) {
      case FamilleActivite.argent:
        return 'Ventes enregistrées, versements encaissés, dépenses et règlements.';
      case FamilleActivite.stock:
        return 'Entrées et sorties de stock, articles créés ou modifiés, prix, clients.';
      case FamilleActivite.administration:
        return 'Comptes et droits, appareils de confiance, fiche entreprise, sauvegardes.';
    }
  }

  void _surReponse(NotificationResponse reponse) {
    final brut = reponse.payload;
    if (brut == null || brut.isEmpty) return;
    try {
      final data = jsonDecode(brut) as Map<String, dynamic>;
      if (_clics.isClosed) return;
      _clics.add(ClicNotification(
        activiteId: data['id']?.toString() ?? '',
        destination: data['destination'] as String?,
      ));
    } catch (e) {
      debugPrint('Charge utile de notification illisible : $e');
    }
  }

  /// Demande la permission d'afficher des notifications.
  ///
  /// À appeler quand l'utilisateur est connecté et a vu l'application, pas au
  /// tout premier écran. Renvoie l'état accordé/refusé ; sur les Android
  /// antérieurs à la version 13, la permission est implicite et la réponse est
  /// « accordée ».
  Future<bool> demanderPermission() async {
    await init();
    if (!_disponible) return false;
    try {
      final android = _greffon.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        _autorise = await android.requestNotificationsPermission() ?? false;
        return _autorise!;
      }
      final ios = _greffon.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        _autorise =
            await ios.requestPermissions(alert: true, badge: true, sound: true) ??
                false;
        return _autorise!;
      }
    } catch (e) {
      debugPrint('Demande de permission de notification refusée : $e');
    }
    _autorise = false;
    return false;
  }

  /// Identifiant système d'une notification, dérivé de l'identifiant de
  /// l'activité.
  ///
  /// Stable : réafficher la même activité remplace sa bannière au lieu d'en
  /// empiler une deuxième. Borné aux entiers 32 bits positifs — Android rejette
  /// silencieusement les identifiants qui débordent — et décalé au-dessus de
  /// [_idResume] pour ne jamais écraser le résumé du groupe.
  static int _idPour(String activiteId) =>
      (activiteId.hashCode & 0x3FFFFFFF) + 100;

  /// Affiche une activité. Sans effet si la permission a été refusée ou si le
  /// greffon n'est pas disponible.
  Future<void> afficher(ActiviteEntree activite) async {
    await init();
    if (!_disponible || _autorise == false) return;

    final destination = activite.destination;
    final charge = jsonEncode({
      'id': activite.id,
      'type': activite.type,
      if (destination != null) 'destination': destination,
    });

    // Le libellé du serveur tient rarement sur une ligne (« Dépense DEP-014
    // enregistrée — Gasoil du camion · 1 250 000 GNF »). Le style « texte long »
    // laisse la bannière se déplier au lieu de couper au milieu du montant.
    final details = AndroidNotificationDetails(
      _idCanal[activite.famille]!,
      kLibelleFamille[activite.famille]!,
      channelDescription: _descriptionCanal(activite.famille),
      importance: activite.famille == FamilleActivite.argent
          ? Importance.high
          : Importance.defaultImportance,
      priority: activite.famille == FamilleActivite.argent
          ? Priority.high
          : Priority.defaultPriority,
      groupKey: _cleGroupe,
      styleInformation: BigTextStyleInformation(
        activite.description,
        contentTitle: activite.titreNotification,
        summaryText: activite.auteur.isEmpty ? null : activite.auteur,
      ),
      ticker: activite.titreNotification,
      showWhen: true,
    );

    try {
      await _greffon.show(
        _idPour(activite.id),
        activite.titreNotification,
        activite.description,
        NotificationDetails(
            android: details, iOS: const DarwinNotificationDetails()),
        payload: charge,
      );
    } catch (e) {
      debugPrint('Notification non affichée : $e');
    }
  }

  /// Pose (ou met à jour) la notification de résumé qui coiffe le groupe.
  ///
  /// Android n'empile les notifications d'un même groupe que si un résumé
  /// existe ; sans lui, quatre ventes en cinq minutes remplissent quatre lignes
  /// du volet. [nombre] est le total de nouveautés non lues.
  Future<void> afficherResume(int nombre) async {
    await init();
    if (!_disponible || _autorise == false || nombre < 2) return;
    try {
      await _greffon.show(
        _idResume,
        'E.A.S Sarlu',
        '$nombre nouvelles activités',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _idCanal[FamilleActivite.argent]!,
            kLibelleFamille[FamilleActivite.argent]!,
            groupKey: _cleGroupe,
            setAsGroupSummary: true,
            importance: Importance.low,
            priority: Priority.low,
            // Le résumé ne doit pas sonner : le bruit a déjà été fait par les
            // notifications qu'il regroupe.
            playSound: false,
            onlyAlertOnce: true,
          ),
        ),
        payload: jsonEncode({'id': '', 'destination': '/activite'}),
      );
    } catch (e) {
      debugPrint('Résumé de notifications non affiché : $e');
    }
  }

  /// Retire toutes les bannières posées par l'application. Appelé quand
  /// l'utilisateur a consulté le journal : garder des bannières « non lues »
  /// après lecture est le meilleur moyen d'apprendre à ne plus les regarder.
  Future<void> toutEffacer() async {
    if (!_disponible) return;
    try {
      await _greffon.cancelAll();
    } catch (e) {
      debugPrint('Effacement des notifications impossible : $e');
    }
  }

  void fermer() {
    if (!_clics.isClosed) _clics.close();
  }
}
