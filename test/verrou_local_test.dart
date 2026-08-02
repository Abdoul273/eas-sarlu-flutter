// Vérifie le verrou local : le code n'est jamais stocké en clair, un mauvais
// code n'ouvre pas, et les essais répétés finissent par imposer une attente.
//
// Ce sont les trois propriétés dont dépend la sécurité de l'application posée
// sur un comptoir, et aucune n'est observable depuis l'interface.
import 'package:eas_sarlu/core/auth/verrou_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage sécurisé en mémoire : les tests ne doivent pas dépendre du trousseau
/// de la machine qui les exécute.
class _StockageMemoire extends FlutterSecureStorage {
  final Map<String, String> valeurs = {};

  _StockageMemoire();

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
      valeurs[key];

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
    if (value == null) {
      valeurs.remove(key);
    } else {
      valeurs[key] = value;
    }
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
    valeurs.remove(key);
  }
}

/// Biométrie absente : c'est le cas le plus courant sur les téléphones du
/// magasin, et celui où le code doit suffire à tout.
class _SansBiometrie extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => false;
  @override
  Future<bool> get canCheckBiometrics async => false;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];
}

void main() {
  late _StockageMemoire stockage;
  late VerrouNotifier verrou;

  setUp(() {
    stockage = _StockageMemoire();
    verrou = VerrouNotifier(stockage, _SansBiometrie());
  });

  group('Définition du code', () {
    test('la première ouverture demande à définir un code', () async {
      await verrou.charger();
      expect(verrou.state.etat, EtatVerrou.aDefinir);
    });

    test('le code n\'est jamais écrit en clair sur l\'appareil', () async {
      await verrou.definirCode('427193');
      expect(stockage.valeurs.values, isNot(contains('427193')));
      expect(stockage.valeurs.values.any((v) => v.contains('427193')), isFalse);
      expect(stockage.valeurs['verrou_empreinte'], isNotNull);
      expect(stockage.valeurs['verrou_sel'], isNotNull);
    });

    test('deux appareils au même code ont des empreintes différentes',
        () async {
      await verrou.definirCode('427193');
      final empreinteA = stockage.valeurs['verrou_empreinte'];

      final stockageB = _StockageMemoire();
      final autre = VerrouNotifier(stockageB, _SansBiometrie());
      await autre.definirCode('427193');

      // Le sel est tiré au hasard : sans lui, une table précalculée du million
      // de codes à six chiffres ouvrirait n'importe quel appareil.
      expect(empreinteA, isNotNull);
      expect(empreinteA, isNot(stockageB.valeurs['verrou_empreinte']));
      expect(verrou.state.longueurCode, 6);
      expect(autre.state.longueurCode, 6);
    });

    test('n\'accepte qu\'un code de six chiffres', () async {
      expect(await verrou.definirCode('4271'), isFalse);
      expect(await verrou.definirCode('42719'), isFalse);
      expect(await verrou.definirCode('4271935'), isFalse);
      expect(await verrou.definirCode('42a193'), isFalse);
      expect(await verrou.definirCode('427193'), isTrue);
    });

    test('signale les codes triviaux', () {
      expect(VerrouNotifier.estCodeFaible('0000'), isTrue);
      expect(VerrouNotifier.estCodeFaible('1234'), isTrue);
      expect(VerrouNotifier.estCodeFaible('4321'), isTrue);
      expect(VerrouNotifier.estCodeFaible('4271'), isFalse);
    });
  });

  group('Déverrouillage', () {
    setUp(() async {
      await verrou.definirCode('427193');
      verrou.verrouiller();
    });

    test('le bon code ouvre', () async {
      expect(
          await verrou.deverrouillerAvecCode('427193'), ResultatVerrou.ouvert);
      expect(verrou.state.etat, EtatVerrou.ouvert);
    });

    test('un mauvais code n\'ouvre pas', () async {
      expect(await verrou.deverrouillerAvecCode('111111'),
          ResultatVerrou.codeIncorrect);
      expect(verrou.state.etat, EtatVerrou.verrouille);
    });

    test('le code survit à un redémarrage de l\'application', () async {
      final apresRedemarrage = VerrouNotifier(stockage, _SansBiometrie());
      await apresRedemarrage.charger();
      expect(apresRedemarrage.state.etat, EtatVerrou.verrouille);
      expect(apresRedemarrage.state.longueurCode, 6);
      expect(await apresRedemarrage.deverrouillerAvecCode('427193'),
          ResultatVerrou.ouvert);
    });

    test('les essais répétés imposent une attente', () async {
      for (var i = 0; i < 3; i++) {
        await verrou.deverrouillerAvecCode('111111');
      }
      expect(verrou.state.echecs, 3);
      expect(verrou.state.enAttente, isTrue);
      // Même le bon code est refusé tant que l'attente court : c'est ce qui
      // rend une recherche exhaustive impraticable.
      expect(await verrou.deverrouillerAvecCode('427193'),
          ResultatVerrou.enAttente);
    });

    test('un déverrouillage réussi remet le compteur à zéro', () async {
      await verrou.deverrouillerAvecCode('111111');
      await verrou.deverrouillerAvecCode('222222');
      expect(verrou.state.echecs, 2);
      await verrou.deverrouillerAvecCode('427193');
      expect(verrou.state.echecs, 0);
      expect(verrou.state.enAttente, isFalse);
      expect(stockage.valeurs['verrou_echecs'], isNull);
    });

    test('l\'attente en cours survit à un redémarrage', () async {
      for (var i = 0; i < 3; i++) {
        await verrou.deverrouillerAvecCode('111111');
      }
      // Redémarrer l'application ne doit pas offrir trois essais de plus.
      final apresRedemarrage = VerrouNotifier(stockage, _SansBiometrie());
      await apresRedemarrage.charger();
      expect(apresRedemarrage.state.echecs, 3);
      expect(apresRedemarrage.state.enAttente, isTrue);
    });
  });

  // Le passage à six chiffres ne doit enfermer personne dehors : les appareils
  // qui portent encore un code de quatre chiffres l'ouvrent comme avant, hors
  // ligne, sans avoir rien à réinitialiser.
  group('Codes hérités', () {
    setUp(() async {
      stockage.valeurs.addAll(enregistrementHerite('4271'));
      await verrou.charger();
    });

    test('un code de quatre chiffres ouvre toujours', () async {
      expect(verrou.state.etat, EtatVerrou.verrouille);
      expect(verrou.state.longueurCode, 4);
      expect(await verrou.deverrouillerAvecCode('4271'), ResultatVerrou.ouvert);
    });

    test('un mauvais code de quatre chiffres n\'ouvre pas', () async {
      expect(await verrou.deverrouillerAvecCode('1111'),
          ResultatVerrou.codeIncorrect);
    });

    test('le remplacer impose six chiffres', () async {
      expect(await verrou.definirCode('1357'), isFalse);
      expect(await verrou.definirCode('427193'), isTrue);
      expect(verrou.state.longueurCode, 6);
    });
  });

  group('Effacement', () {
    test('la déconnexion efface toute trace du code', () async {
      await verrou.definirCode('427193');
      await verrou.effacer();
      expect(stockage.valeurs['verrou_empreinte'], isNull);
      expect(stockage.valeurs['verrou_sel'], isNull);
      expect(verrou.state.etat, EtatVerrou.aDefinir);
    });
  });
}
