import 'package:eas_sarlu/core/models/activite.dart';
import 'package:eas_sarlu/core/services/notification_service.dart';
import 'package:eas_sarlu/features/activite/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service factice : on ne vérifie pas qu'Android affiche quelque chose, mais
/// que le fil DÉCIDE d'afficher la bonne chose.
class _ServiceEspion extends NotificationService {
  final List<ActiviteEntree> affichees = [];
  final List<int> resumes = [];
  int effacements = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> afficher(ActiviteEntree activite) async {
    affichees.add(activite);
  }

  @override
  Future<void> afficherResume(int nombre) async {
    resumes.add(nombre);
  }

  @override
  Future<void> toutEffacer() async {
    effacements++;
  }

  @override
  Future<bool> demanderPermission() async => true;
}

ActiviteEntree _act(
  String id, {
  required String date,
  String type = 'vente',
  String auteur = 'Mamadou',
  String libelle = 'Vente VTE-001 — 500 000 GNF',
}) =>
    ActiviteEntree(
      id: id,
      type: type,
      description: libelle,
      auteur: auteur,
      date: date,
    );

void main() {
  late SharedPreferences prefs;
  late _ServiceEspion service;

  Future<NotificationsNotifier> creer({String? moi = 'Abdoul'}) async {
    final notifier = NotificationsNotifier(
      service: service,
      prefs: prefs,
      nomUtilisateur: () => moi,
    );
    // Le constructeur relit les repères persistés de façon synchrone ; on laisse
    // néanmoins la boucle tourner, comme en conditions réelles.
    await Future<void>.delayed(Duration.zero);
    return notifier;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = _ServiceEspion();
  });

  group('Premier instantané', () {
    test("n'affiche rien : l'historique n'est pas une nouveauté", () async {
      final notifier = await creer();
      await notifier.ingerer([
        _act('a1', date: '2026-08-01T10:00:00.000Z'),
        _act('a2', date: '2026-07-30T10:00:00.000Z'),
        _act('a3', date: '2026-01-05T10:00:00.000Z'),
      ]);

      expect(service.affichees, isEmpty,
          reason: 'un rattrapage de tout le journal ferait fuir '
              "l'utilisateur dès la première ouverture");
      expect(service.resumes, isEmpty);
      // Le badge non plus ne s'allume pas sur un passé que personne n'a demandé.
      expect(notifier.state.aDuNonLu, isFalse);
      expect(notifier.state.recentes, hasLength(3));
    });

    test('pose un repère qui rend le lot suivant notifiable', () async {
      final notifier = await creer();
      await notifier.ingerer([_act('a1', date: '2026-08-01T10:00:00.000Z')]);
      await notifier.ingerer([
        _act('a2', date: '2026-08-01T11:00:00.000Z'),
        _act('a1', date: '2026-08-01T10:00:00.000Z'),
      ]);

      expect(service.affichees.map((a) => a.id), ['a2']);
    });
  });

  group('Ce qui mérite une bannière', () {
    test('ignore les activités dont on est soi-même l\'auteur', () async {
      final notifier = await creer(moi: 'Abdoul');
      await notifier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);

      await notifier.ingerer([
        _act('a1', date: '2026-08-01T10:00:00.000Z', auteur: 'Abdoul'),
        _act('a2', date: '2026-08-01T10:30:00.000Z', auteur: 'Mamadou'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ]);

      expect(service.affichees.map((a) => a.id), ['a2']);
      expect(notifier.state.recentes.map((a) => a.id), isNot(contains('a1')));
    });

    test('la casse et les espaces du nom ne trompent pas la comparaison',
        () async {
      final notifier = await creer(moi: '  abdoul  ');
      await notifier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);
      await notifier.ingerer([
        _act('a1', date: '2026-08-01T10:00:00.000Z', auteur: 'Abdoul'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ]);

      expect(service.affichees, isEmpty);
    });

    test("n'affiche jamais deux fois la même entrée", () async {
      final notifier = await creer();
      await notifier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);

      final lot = [
        _act('a1', date: '2026-08-01T10:00:00.000Z'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ];
      await notifier.ingerer(lot);
      await notifier.ingerer(lot);
      await notifier.ingerer(lot);

      expect(service.affichees.map((a) => a.id), ['a1']);
    });

    test('plafonne les bannières et résume le reste', () async {
      final notifier = await creer();
      await notifier.ingerer([_act('a0', date: '2026-08-01T00:00:00.000Z')]);

      // Retour d'une journée hors ligne : douze activités d'un coup.
      final lot = [
        for (var i = 1; i <= 12; i++)
          _act('n$i', date: '2026-08-01T10:${i.toString().padLeft(2, '0')}:00.000Z'),
        _act('a0', date: '2026-08-01T00:00:00.000Z'),
      ];
      await notifier.ingerer(lot);

      expect(service.affichees, hasLength(5),
          reason: 'douze bannières d\'un coup rendent le volet illisible');
      expect(service.resumes, [12]);
      // Les cinq affichées sont bien les plus récentes.
      expect(service.affichees.map((a) => a.id).toSet(),
          {'n8', 'n9', 'n10', 'n11', 'n12'});
    });

    test('les entrées sans date lisible ne déclenchent rien', () async {
      final notifier = await creer();
      await notifier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);
      await notifier.ingerer([
        _act('bancale', date: 'pas une date'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ]);

      expect(service.affichees, isEmpty);
    });

    test('une date en millisecondes se lit comme une date ISO', () async {
      final ancienne = DateTime.utc(2026, 8, 1, 9);
      final recente = DateTime.utc(2026, 8, 1, 10);
      final notifier = await creer();
      await notifier
          .ingerer([_act('a0', date: '${ancienne.millisecondsSinceEpoch}')]);
      await notifier.ingerer([
        _act('a1', date: '${recente.millisecondsSinceEpoch}'),
        _act('a0', date: '${ancienne.millisecondsSinceEpoch}'),
      ]);

      expect(service.affichees.map((a) => a.id), ['a1']);
    });
  });

  group('Lecture', () {
    test('marquer lu éteint le badge et efface les bannières', () async {
      final notifier = await creer();
      await notifier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);
      await notifier.ingerer([
        _act('a1', date: '2026-08-01T10:00:00.000Z'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ]);
      expect(notifier.state.nombreNonLues, 1);

      await notifier.marquerLu();

      expect(notifier.state.aDuNonLu, isFalse);
      expect(service.effacements, 1);
      // La liste reste consultable : marquer lu n'est pas effacer.
      expect(notifier.state.recentes, hasLength(2));
    });

    test('le repère de lecture suit la dernière activité, pas l\'horloge',
        () async {
      // Une horloge de téléphone en avance masquerait les activités arrivées
      // entre-temps, qui ne reviendraient jamais dans le badge.
      final notifier = await creer();
      await notifier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);
      await notifier.ingerer([
        _act('a1', date: '2026-08-01T10:00:00.000Z'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ]);
      await notifier.marquerLu();

      expect(notifier.state.dernierLu,
          DateTime.parse('2026-08-01T10:00:00.000Z'));
      expect(prefs.getString('eas_notif_dernier_lu'), isNotNull);
    });

    test('le repère survit à un redémarrage', () async {
      final premier = await creer();
      await premier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);
      await premier.ingerer([
        _act('a1', date: '2026-08-01T10:00:00.000Z'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ]);
      premier.dispose();

      // Nouveau démarrage, même téléphone : les repères sont relus, donc rien
      // n'est resignalé.
      service = _ServiceEspion();
      final second = await creer();
      await second.ingerer([
        _act('a1', date: '2026-08-01T10:00:00.000Z'),
        _act('a0', date: '2026-08-01T09:00:00.000Z'),
      ]);

      expect(service.affichees, isEmpty);
    });

    test('changer de compte remet le fil à zéro', () async {
      final notifier = await creer();
      await notifier.ingerer([_act('a0', date: '2026-08-01T09:00:00.000Z')]);
      await notifier.reinitialiser();

      expect(prefs.getString('eas_notif_dernier_notifie'), isNull);
      expect(prefs.getString('eas_notif_dernier_lu'), isNull);
      expect(notifier.state.recentes, isEmpty);

      // Et le compte suivant repart sur un premier instantané muet.
      await notifier.ingerer([_act('a1', date: '2026-08-02T09:00:00.000Z')]);
      expect(service.affichees, isEmpty);
    });
  });

  group('Modèle ActiviteEntree', () {
    test('chaque type émis par le serveur a une famille et un titre', () {
      for (final type in kTypesActivite.keys) {
        final a = _act('x', date: '2026-08-01T09:00:00.000Z', type: type);
        expect(kTitreNotification[type], isNotNull,
            reason: 'le type « $type » n\'a pas de titre lisible');
        expect(a.titreNotification, isNot('Activité enregistrée'));
      }
    });

    test('la destination mène à la page de l\'objet visé', () {
      const facture = ActiviteEntree(
        id: 'x',
        type: 'facture',
        description: 'Versement',
        auteur: 'Mamadou',
        date: '2026-08-01T09:00:00.000Z',
        cibleKind: 'facture',
        cibleId: 'FAC-42',
      );
      expect(facture.destination, '/factures/FAC-42');

      const sansCible = ActiviteEntree(
        id: 'y',
        type: 'sauvegarde',
        description: 'Sauvegarde effectuée',
        auteur: 'Mamadou',
        date: '2026-08-01T09:00:00.000Z',
      );
      expect(sansCible.destination, isNull);
    });
  });
}
