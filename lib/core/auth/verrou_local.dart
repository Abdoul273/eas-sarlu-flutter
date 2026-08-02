import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_state.dart';

// ─── Verrou local ─────────────────────────────────────────────────────────────
// Le code à 4-6 chiffres qui protège l'application entre deux ouvertures.
//
// Il n'a rien à voir avec la connexion au compte : celle-ci se fait une fois,
// à l'installation, et la session est ensuite conservée. Le verrou, lui, se
// referme à chaque fermeture de l'application et se rouvre sans réseau — c'est
// précisément le cas d'usage du magasin, où la connexion va et vient.
//
// Le code n'est jamais écrit sur l'appareil. Seule son empreinte l'est
// (PBKDF2-HMAC-SHA256, sel aléatoire de 16 octets), de sorte qu'un accès au
// stockage du téléphone ne livre pas le code. La vérification recalcule
// l'empreinte et la compare en temps constant : une comparaison qui s'arrête
// au premier octet différent laisse fuir, par sa durée, la longueur du préfixe
// correct.

/// Nombre d'itérations PBKDF2. Assez élevé pour qu'une recherche exhaustive sur
/// les 10⁶ codes possibles coûte cher, assez bas pour que le déverrouillage
/// reste instantané sur un téléphone d'entrée de gamme.
const _iterations = 100000;
const _longueurCle = 32;

const _cleEmpreinte = 'verrou_empreinte';
const _cleSel = 'verrou_sel';
const _cleLongueur = 'verrou_longueur';
const _cleBiometrie = 'verrou_biometrie';
const _cleEchecs = 'verrou_echecs';
const _cleBlocageJusqua = 'verrou_blocage_jusqua';

/// Longueur d'un code créé aujourd'hui. Six chiffres, ni plus ni moins : un
/// choix laissé à l'utilisateur ne servait qu'à lui faire prendre quatre, et le
/// pavé devait alors afficher une touche « Valider » puisque rien n'indiquait
/// la fin de la saisie. À longueur fixe, le code part tout seul au sixième
/// chiffre — un geste de moins, cent fois par jour.
const int longueurCodeRequise = 6;

/// Longueur minimale encore acceptée à la *vérification*. Les codes de 4 ou 5
/// chiffres créés avant ce changement restent valables : imposer six chiffres
/// d'un coup aurait enfermé dehors ceux qui les utilisent, hors ligne et sans
/// recours. Ils passeront à six à leur prochain changement de code.
const int longueurCodeMin = 4;
const int longueurCodeMax = 6;

/// Au-delà de ce nombre d'essais manqués, chaque nouvel échec impose une
/// attente. On ne détruit rien et on ne déconnecte pas : le gérant qui se
/// trompe trois fois de suite ne doit pas perdre l'accès à ses données ni être
/// renvoyé vers une page de connexion qu'il ne pourra pas passer hors ligne.
const int _echecsAvantAttente = 3;

/// Attente imposée après [_echecsAvantAttente] échecs, en secondes, par palier.
/// Le dernier palier se répète indéfiniment.
const List<int> _paliersAttente = [15, 30, 60, 120, 300];

enum EtatVerrou {
  /// Le chargement de l'état n'est pas terminé.
  inconnu,

  /// Aucun code n'a encore été défini : première ouverture après la connexion.
  aDefinir,

  /// Un code existe et l'application est fermée à clé.
  verrouille,

  /// L'utilisateur a passé le verrou pour cette session d'utilisation.
  ouvert,
}

@immutable
class VerrouState {
  final EtatVerrou etat;

  /// Longueur du code réellement enregistré, pour que la saisie sache quand
  /// valider. Six pour tout code créé aujourd'hui ; quatre ou cinq pour un code
  /// hérité que l'on continue d'accepter.
  final int longueurCode;

  /// La biométrie est disponible sur l'appareil ET activée par l'utilisateur.
  final bool biometrieActive;

  /// La biométrie est proposée par l'appareil (empreinte ou visage enrôlés).
  final bool biometrieDisponible;

  /// Échecs consécutifs depuis le dernier déverrouillage réussi.
  final int echecs;

  /// Instant avant lequel toute tentative est refusée. `null` si libre.
  final DateTime? blocageJusqua;

  const VerrouState({
    this.etat = EtatVerrou.inconnu,
    this.longueurCode = longueurCodeRequise,
    this.biometrieActive = false,
    this.biometrieDisponible = false,
    this.echecs = 0,
    this.blocageJusqua,
  });

  /// Secondes restantes avant de pouvoir réessayer. 0 si aucune attente.
  int get secondesAttente {
    final jusqua = blocageJusqua;
    if (jusqua == null) return 0;
    final reste = jusqua.difference(DateTime.now()).inSeconds;
    return reste > 0 ? reste : 0;
  }

  bool get enAttente => secondesAttente > 0;

  VerrouState copyWith({
    EtatVerrou? etat,
    int? longueurCode,
    bool? biometrieActive,
    bool? biometrieDisponible,
    int? echecs,
    DateTime? blocageJusqua,
    bool effacerBlocage = false,
  }) =>
      VerrouState(
        etat: etat ?? this.etat,
        longueurCode: longueurCode ?? this.longueurCode,
        biometrieActive: biometrieActive ?? this.biometrieActive,
        biometrieDisponible: biometrieDisponible ?? this.biometrieDisponible,
        echecs: echecs ?? this.echecs,
        blocageJusqua: effacerBlocage ? null : (blocageJusqua ?? this.blocageJusqua),
      );
}

/// Résultat d'une tentative de déverrouillage, pour que l'écran sache quoi dire.
enum ResultatVerrou { ouvert, codeIncorrect, enAttente, indisponible }

class VerrouNotifier extends StateNotifier<VerrouState> {
  final FlutterSecureStorage _stockage;
  final LocalAuthentication _biometrie;

  VerrouNotifier(this._stockage, this._biometrie) : super(const VerrouState());

  /// Charge l'état du verrou au démarrage. À appeler une fois, avant d'afficher
  /// quoi que ce soit : c'est lui qui décide si l'on montre la saisie du code.
  Future<void> charger() async {
    final empreinte = await _stockage.read(key: _cleEmpreinte);
    final longueur =
        int.tryParse(await _stockage.read(key: _cleLongueur) ?? '') ??
            longueurCodeRequise;
    final biometrieVoulue =
        (await _stockage.read(key: _cleBiometrie)) == 'oui';
    final echecs = int.tryParse(await _stockage.read(key: _cleEchecs) ?? '') ?? 0;
    final blocage =
        DateTime.tryParse(await _stockage.read(key: _cleBlocageJusqua) ?? '');

    final disponible = await _biometrieDisponible();

    state = VerrouState(
      etat: (empreinte == null || empreinte.isEmpty)
          ? EtatVerrou.aDefinir
          : EtatVerrou.verrouille,
      longueurCode: longueur,
      biometrieDisponible: disponible,
      biometrieActive: biometrieVoulue && disponible,
      echecs: echecs,
      blocageJusqua: blocage,
    );
  }

  /// Redemande au téléphone s'il a une empreinte enrôlée.
  ///
  /// La réponse n'était lue qu'au démarrage. Quelqu'un à qui l'on dit « ajoutez
  /// une empreinte dans les réglages Android » revenait donc sur une bascule
  /// toujours grise, sans autre remède que de redémarrer l'application — ce
  /// que personne ne devine.
  Future<void> rafraichirBiometrie() async {
    final disponible = await _biometrieDisponible();
    final voulue = (await _stockage.read(key: _cleBiometrie)) == 'oui';
    state = state.copyWith(
        biometrieDisponible: disponible, biometrieActive: voulue && disponible);
  }

  Future<bool> _biometrieDisponible() async {
    try {
      if (!await _biometrie.isDeviceSupported()) return false;
      if (!await _biometrie.canCheckBiometrics) return false;
      // Un appareil « capable » sans empreinte enrôlée ferait échouer chaque
      // tentative sans que l'utilisateur comprenne pourquoi : on ne propose la
      // biométrie que si elle est réellement configurée.
      return (await _biometrie.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Définit le code à la première ouverture, ou le remplace depuis les
  /// paramètres. Retourne `false` si la longueur n'est pas admise.
  Future<bool> definirCode(String code) async {
    if (!estCodeValide(code)) return false;
    final sel = _nouveauSel();
    final empreinte = _empreinte(code, sel);
    await _stockage.write(key: _cleSel, value: base64Encode(sel));
    await _stockage.write(key: _cleEmpreinte, value: base64Encode(empreinte));
    await _stockage.write(key: _cleLongueur, value: '${code.length}');
    await _reinitialiserEchecs();
    state = state.copyWith(
      etat: EtatVerrou.ouvert,
      longueurCode: code.length,
      echecs: 0,
      effacerBlocage: true,
    );
    return true;
  }

  /// Un code créé aujourd'hui fait exactement [longueurCodeRequise] chiffres.
  /// La longueur variable ne servait qu'à en prendre quatre ; six chiffres
  /// multiplient par cent le coût d'une recherche exhaustive, pour deux frappes
  /// de plus.
  static bool estCodeValide(String code) {
    if (code.length != longueurCodeRequise) return false;
    if (!RegExp(r'^\d+$').hasMatch(code)) return false;
    return true;
  }

  /// Vrai si le code est admis mais déconseillé (chiffres identiques ou suite).
  static bool estCodeFaible(String code) {
    if (code.split('').toSet().length == 1) return true;
    var croissant = true, decroissant = true;
    for (var i = 1; i < code.length; i++) {
      final ecart = code.codeUnitAt(i) - code.codeUnitAt(i - 1);
      if (ecart != 1) croissant = false;
      if (ecart != -1) decroissant = false;
    }
    return croissant || decroissant;
  }

  /// Vérifie le code saisi et ouvre le verrou s'il est bon.
  Future<ResultatVerrou> deverrouillerAvecCode(String code) async {
    if (state.enAttente) return ResultatVerrou.enAttente;

    final selEncode = await _stockage.read(key: _cleSel);
    final empreinteEncodee = await _stockage.read(key: _cleEmpreinte);
    if (selEncode == null || empreinteEncodee == null) {
      // Aucun code enregistré : il faut en définir un plutôt que d'échouer.
      state = state.copyWith(etat: EtatVerrou.aDefinir);
      return ResultatVerrou.indisponible;
    }

    final attendue = base64Decode(empreinteEncodee);
    final calculee = _empreinte(code, base64Decode(selEncode));

    if (!_egalesEnTempsConstant(attendue, calculee)) {
      await _enregistrerEchec();
      return ResultatVerrou.codeIncorrect;
    }

    await _reinitialiserEchecs();
    state = state.copyWith(
        etat: EtatVerrou.ouvert, echecs: 0, effacerBlocage: true);
    return ResultatVerrou.ouvert;
  }

  /// Propose le déverrouillage par empreinte. Un refus ou un échec ne compte
  /// pas comme un essai manqué : le code reste la voie de secours.
  Future<ResultatVerrou> deverrouillerAvecBiometrie() async {
    if (!state.biometrieActive) return ResultatVerrou.indisponible;
    if (state.enAttente) return ResultatVerrou.enAttente;
    try {
      final ok = await _biometrie.authenticate(
        localizedReason: 'Déverrouillez E.A.S Sarlu',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
      if (!ok) return ResultatVerrou.indisponible;
      await _reinitialiserEchecs();
      state = state.copyWith(
          etat: EtatVerrou.ouvert, echecs: 0, effacerBlocage: true);
      return ResultatVerrou.ouvert;
    } catch (_) {
      return ResultatVerrou.indisponible;
    }
  }

  /// Active ou coupe le déverrouillage par empreinte. L'activation exige une
  /// authentification réussie sur-le-champ : sans cela, on enregistrerait une
  /// préférence pour un capteur qui ne répond pas.
  Future<bool> definirBiometrie(bool active) async {
    if (!active) {
      await _stockage.write(key: _cleBiometrie, value: 'non');
      state = state.copyWith(biometrieActive: false);
      return true;
    }
    if (!await _biometrieDisponible()) return false;
    try {
      final ok = await _biometrie.authenticate(
        localizedReason: 'Confirmez pour activer le déverrouillage biométrique',
        options: const AuthenticationOptions(
            stickyAuth: true, biometricOnly: true, useErrorDialogs: true),
      );
      if (!ok) return false;
    } catch (_) {
      return false;
    }
    await _stockage.write(key: _cleBiometrie, value: 'oui');
    state = state.copyWith(biometrieActive: true, biometrieDisponible: true);
    return true;
  }

  /// Referme le verrou : appelé quand l'application repasse au premier plan.
  void verrouiller() {
    if (state.etat == EtatVerrou.ouvert) {
      state = state.copyWith(etat: EtatVerrou.verrouille);
    }
  }

  /// Efface toute trace du verrou. Appelé à la déconnexion du compte : le code
  /// protège une session, il n'a plus de sens une fois celle-ci partie.
  Future<void> effacer() async {
    await _stockage.delete(key: _cleEmpreinte);
    await _stockage.delete(key: _cleSel);
    await _stockage.delete(key: _cleLongueur);
    await _stockage.delete(key: _cleBiometrie);
    await _reinitialiserEchecs();
    state = const VerrouState(etat: EtatVerrou.aDefinir);
  }

  Future<void> _enregistrerEchec() async {
    final echecs = state.echecs + 1;
    await _stockage.write(key: _cleEchecs, value: '$echecs');

    DateTime? jusqua;
    if (echecs >= _echecsAvantAttente) {
      final palier = (echecs - _echecsAvantAttente).clamp(0, _paliersAttente.length - 1);
      jusqua = DateTime.now().add(Duration(seconds: _paliersAttente[palier]));
      await _stockage.write(
          key: _cleBlocageJusqua, value: jusqua.toIso8601String());
    }
    state = state.copyWith(echecs: echecs, blocageJusqua: jusqua);
  }

  Future<void> _reinitialiserEchecs() async {
    await _stockage.delete(key: _cleEchecs);
    await _stockage.delete(key: _cleBlocageJusqua);
  }

  /// Rafraîchit l'attente affichée pendant le décompte.
  void rafraichirAttente() {
    if (state.blocageJusqua != null && !state.enAttente) {
      state = state.copyWith(effacerBlocage: true);
    } else {
      // Force une notification pour que le décompte se réaffiche.
      state = state.copyWith();
    }
  }
}

// ─── Empreinte ────────────────────────────────────────────────────────────────

/// Fabrique l'enregistrement qu'aurait laissé une version antérieure de
/// l'application, du temps où un code de quatre chiffres était admis.
///
/// C'est le seul moyen de vérifier que ces codes ouvrent toujours : `definirCode`
/// les refuse désormais, et un test qui ne pourrait pas les créer ne pourrait
/// pas non plus prouver qu'on n'a enfermé personne dehors.
@visibleForTesting
Map<String, String> enregistrementHerite(String code) {
  final sel = _nouveauSel();
  return {
    _cleSel: base64Encode(sel),
    _cleEmpreinte: base64Encode(_empreinte(code, sel)),
    _cleLongueur: '${code.length}',
  };
}

List<int> _nouveauSel() {
  final aleatoire = Random.secure();
  return List<int>.generate(16, (_) => aleatoire.nextInt(256));
}

/// PBKDF2-HMAC-SHA256, écrit à la main : `crypto` fournit HMAC mais pas la
/// dérivation. L'algorithme tient en quinze lignes et évite d'ajouter une
/// dépendance de plus pour un usage unique.
List<int> _empreinte(String code, List<int> sel) {
  final hmac = Hmac(sha256, utf8.encode(code));
  final resultat = List<int>.filled(_longueurCle, 0);
  var offset = 0;
  var bloc = 1;

  while (offset < _longueurCle) {
    // U1 = HMAC(mot de passe, sel ‖ INT_32_BE(bloc))
    var u = hmac
        .convert([...sel, (bloc >> 24) & 0xff, (bloc >> 16) & 0xff, (bloc >> 8) & 0xff, bloc & 0xff])
        .bytes;
    final accumulateur = List<int>.from(u);
    for (var i = 1; i < _iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < accumulateur.length; j++) {
        accumulateur[j] ^= u[j];
      }
    }
    final aCopier = (_longueurCle - offset).clamp(0, accumulateur.length);
    resultat.setRange(offset, offset + aCopier, accumulateur);
    offset += aCopier;
    bloc++;
  }
  return resultat;
}

/// Comparaison à durée constante : on parcourt toujours toute la longueur.
bool _egalesEnTempsConstant(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

// ─── Providers ────────────────────────────────────────────────────────────────

final localAuthProvider = Provider<LocalAuthentication>((ref) {
  return LocalAuthentication();
});

final verrouProvider = StateNotifierProvider<VerrouNotifier, VerrouState>((ref) {
  return VerrouNotifier(
      ref.watch(secureStorageProvider), ref.watch(localAuthProvider));
});
