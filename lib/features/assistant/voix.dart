import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart' show sharedPreferencesProvider;
import 'ai_config.dart';
import 'voix_neurale.dart';

// ─── Lecture à voix haute des réponses de l'assistant ─────────────────────────
// Le magasin se tient debout, les mains prises. Lire une analyse de trésorerie
// sur un téléphone posé sur le comptoir demande de s'arrêter ; l'écouter, non.
//
// Deux voix cohabitent ici, et le choix entre elles est un vrai arbitrage :
//
//   • Celle du téléphone. Pas de clé, pas d'appel réseau, pas de quota, et elle
//     fonctionne quand la connexion tombe — comme le reste de l'application. On
//     ne choisit pas la voix, on choisit parmi celles qui sont installées :
//     d'où la sélection de la meilleure voix française disponible.
//
//   • Celle de Gemini. Naturelle au point qu'on ne l'entend pas comme une
//     machine, et pilotable au ton près. Mais elle a besoin du réseau et d'une
//     clé, et elle se facture.
//
// La neuronale est proposée par défaut quand une clé Gemini existe, et **tout
// échec de sa part bascule silencieusement sur celle du téléphone**. C'est la
// règle qui compte : le commerçant qui appuie sur « Écouter » doit entendre
// quelque chose, quelle que soit la couverture réseau du quartier.

/// Une voix française proposée par le moteur du téléphone.
@immutable
class VoixDisponible {
  final String nom;
  final String locale;

  /// Note interne servant à désigner la meilleure voix par défaut.
  final int qualite;

  const VoixDisponible({
    required this.nom,
    required this.locale,
    required this.qualite,
  });

  /// Les moteurs Android nomment leurs voix « fr-fr-x-frd#female_2-local » :
  /// illisible tel quel. On en tire quelque chose qui se choisit dans une liste.
  String get libelle {
    final n = nom.toLowerCase();
    final morceaux = <String>[];

    if (n.contains('female') || n.contains('femme')) {
      morceaux.add('Voix féminine');
    } else if (n.contains('male') || n.contains('homme')) {
      morceaux.add('Voix masculine');
    } else {
      morceaux.add(nom);
    }

    final numero = RegExp(r'_(\d+)').firstMatch(n)?.group(1);
    if (numero != null && morceaux.first.startsWith('Voix')) {
      morceaux[0] = '${morceaux[0]} $numero';
    }

    if (_estPremium(n)) morceaux.add('haute qualité');
    if (n.contains('network')) morceaux.add('en ligne');

    if (!locale.toLowerCase().startsWith('fr-fr')) morceaux.add(locale);

    return morceaux.length == 1
        ? morceaux.first
        : '${morceaux.first} — ${morceaux.skip(1).join(', ')}';
  }

  Map<String, String> get pourMoteur => {'name': nom, 'locale': locale};
}

bool _estPremium(String nomMinuscule) =>
    nomMinuscule.contains('enhanced') ||
    nomMinuscule.contains('premium') ||
    nomMinuscule.contains('neural') ||
    nomMinuscule.contains('wavenet') ||
    nomMinuscule.contains('siri');

/// Classe les voix françaises de la meilleure à la moins bonne.
///
/// On privilégie ce qui sonne juste — les voix « enhanced » d'iOS, « neural »
/// ou « wavenet » d'Android — mais on garde un net avantage aux voix locales :
/// une voix réseau se tait dès que la connexion tombe, ce qui arrive tous les
/// jours ici.
int _noterVoix(String nom, String locale) {
  final n = nom.toLowerCase();
  var note = 0;
  if (locale.toLowerCase().startsWith('fr-fr')) note += 100;
  if (_estPremium(n)) note += 40;
  if (n.contains('network')) {
    note -= 25;
  } else if (n.contains('local')) {
    note += 25;
  }
  return note;
}

/// Qui prononce.
enum MoteurVoix {
  /// La synthèse installée sur le téléphone. Gratuite, hors ligne, mécanique.
  appareil,

  /// Gemini TTS. Naturelle, pilotable au ton, mais en ligne et facturée.
  neurale,
}

@immutable
class ConfigVoix {
  /// La lecture est proposée. Coupée, aucun bouton « Écouter » n'apparaît.
  final bool active;

  /// Lire d'elle-même chaque nouvelle réponse, sans avoir à appuyer.
  final bool lectureAuto;

  /// Le moteur préféré. `neurale` reste un souhait : sans clé ni réseau, la
  /// lecture se fait quand même, par le téléphone.
  final MoteurVoix moteur;

  /// La voix Gemini retenue, quand le moteur neuronal est choisi.
  final String voixNeurale;

  /// Nom de la voix choisie ; `null` = la meilleure voix française trouvée.
  final String? voix;

  /// Multiplicateur de débit autour du débit normal du moteur (1 = normal).
  ///
  /// Par défaut légèrement en dessous : à débit exactement normal, la synthèse
  /// enchaîne les chiffres sans reprendre son souffle et s'entend comme une
  /// machine. Un cran plus bas suffit à ce qu'elle s'entende comme quelqu'un.
  final double vitesse;

  /// Hauteur du timbre (1 = celle du moteur).
  final double hauteur;

  const ConfigVoix({
    this.active = true,
    this.lectureAuto = false,
    this.moteur = MoteurVoix.neurale,
    this.voixNeurale = kVoixNeuraleParDefaut,
    this.voix,
    this.vitesse = vitesseNaturelle,
    this.hauteur = 1.0,
  });

  /// Le débit posé qu'on veut par défaut : celui d'une phrase dite, pas lue.
  static const double vitesseNaturelle = 0.9;

  ConfigVoix copyWith({
    bool? active,
    bool? lectureAuto,
    MoteurVoix? moteur,
    String? voixNeurale,
    String? voix,
    bool effacerVoix = false,
    double? vitesse,
    double? hauteur,
  }) =>
      ConfigVoix(
        active: active ?? this.active,
        lectureAuto: lectureAuto ?? this.lectureAuto,
        moteur: moteur ?? this.moteur,
        voixNeurale: voixNeurale ?? this.voixNeurale,
        voix: effacerVoix ? null : (voix ?? this.voix),
        vitesse: vitesse ?? this.vitesse,
        hauteur: hauteur ?? this.hauteur,
      );

  Map<String, dynamic> toJson() => {
        'v': _versionEchelle,
        'active': active,
        'lectureAuto': lectureAuto,
        'moteur': moteur.name,
        'voixNeurale': voixNeurale,
        'voix': voix,
        'vitesse': vitesse,
        'hauteur': hauteur,
      };

  /// Le débit enregistré avant la correction du débit neutre (voir
  /// [VoixNotifier._debitPlateforme]) désigne une autre vitesse réelle : qui
  /// avait descendu le curseur pour compenser se retrouverait au ralenti. On
  /// repart du débit naturel plutôt que de traîner l'ancien réglage.
  static const int _versionEchelle = 2;

  factory ConfigVoix.fromJson(Map<String, dynamic> json) {
    final ancienneEchelle = (json['v'] as num?)?.toInt() != _versionEchelle;
    final voixN = json['voixNeurale'] as String?;
    return ConfigVoix(
      active: json['active'] != false,
      lectureAuto: json['lectureAuto'] == true,
      moteur: MoteurVoix.values.firstWhere(
        (m) => m.name == json['moteur'],
        // Un réglage enregistré avant l'arrivée de la voix neuronale n'a pas ce
        // champ : on lui propose la meilleure voix, il coupera s'il préfère.
        orElse: () => MoteurVoix.neurale,
      ),
      voixNeurale: kVoixNeurales.any((v) => v.id == voixN)
          ? voixN!
          : kVoixNeuraleParDefaut,
      voix: json['voix'] as String?,
      vitesse: ancienneEchelle
          ? vitesseNaturelle
          : (json['vitesse'] as num?)?.toDouble().clamp(0.5, 2.0) ??
              vitesseNaturelle,
      hauteur: (json['hauteur'] as num?)?.toDouble().clamp(0.5, 2.0) ?? 1.0,
    );
  }
}

@immutable
class EtatVoix {
  final ConfigVoix config;

  /// Voix françaises installées sur ce téléphone.
  final List<VoixDisponible> voixDisponibles;

  /// Identifiant du message en cours de lecture, `null` si l'on se tait.
  final String? enLecture;

  /// Le moteur a répondu à l'inventaire des voix. Tant que c'est faux, on ne
  /// sait pas encore si la lecture est possible.
  final bool pret;

  /// La voix neuronale était demandée mais n'a pas pu répondre, et c'est le
  /// téléphone qui a lu. Affiché une fois dans les réglages : sans cela, le
  /// commerçant croit avoir mal réglé quelque chose.
  final String? repliVoix;

  /// Une synthèse neuronale est en cours de fabrication : elle prend une
  /// seconde ou deux, pendant lesquelles il ne se passe rien d'audible.
  final bool prepare;

  /// Aucune voix française n'est installée : on le dit plutôt que de laisser
  /// un bouton muet. La voix neuronale, elle, n'a besoin d'aucune installation.
  bool get indisponible =>
      pret && voixDisponibles.isEmpty && config.moteur != MoteurVoix.neurale;

  const EtatVoix({
    this.config = const ConfigVoix(),
    this.voixDisponibles = const [],
    this.enLecture,
    this.pret = false,
    this.repliVoix,
    this.prepare = false,
  });

  EtatVoix copyWith({
    ConfigVoix? config,
    List<VoixDisponible>? voixDisponibles,
    String? enLecture,
    bool effacerLecture = false,
    bool? pret,
    String? repliVoix,
    bool effacerRepli = false,
    bool? prepare,
  }) =>
      EtatVoix(
        config: config ?? this.config,
        voixDisponibles: voixDisponibles ?? this.voixDisponibles,
        enLecture: effacerLecture ? null : (enLecture ?? this.enLecture),
        pret: pret ?? this.pret,
        repliVoix: effacerRepli ? null : (repliVoix ?? this.repliVoix),
        prepare: prepare ?? this.prepare,
      );
}

const _cleConfigVoix = 'voix_config';

/// `dart:io` plutôt que `defaultTargetPlatform` obligerait à exclure la cible
/// web à la compilation ; la constante de `foundation` répond partout.
bool get _estApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Au-delà, le moteur Android refuse l'énoncé d'un bloc. On découpe donc les
/// longues réponses — celles qui méritent le plus d'être écoutées.
const int _maxParEnonce = 3500;

/// Longueur visée d'un souffle. Au-delà, la synthèse enchaîne sans reprendre
/// son air : c'est ce qui la trahit le plus vite.
const int _cibleSouffle = 220;

/// Silences rendus à la ponctuation. Les moteurs marquent le point d'un temps
/// si court qu'un paragraphe entier s'entend comme une seule phrase.
const Duration _pauseEntrePhrases = Duration(milliseconds: 170);
const Duration _pauseEntreLignes = Duration(milliseconds: 340);

class VoixNotifier extends StateNotifier<EtatVoix> {
  final SharedPreferences _prefs;
  final FlutterTts _moteur;
  final AudioPlayer _lecteur;
  final VoixNeuraleClient _neurale;

  /// Comment joindre la configuration IA au moment de parler. La voix
  /// neuronale se paie sur la clé Gemini de l'assistant : la lire à la
  /// construction figerait une clé saisie plus tard.
  final ConfigIA Function() _configIA;

  /// Incrémenté à chaque nouvelle lecture. Une lecture découpée en plusieurs
  /// énoncés vérifie ce jeton entre deux morceaux : sans cela, appuyer sur
  /// « Arrêter » couperait le morceau en cours et le suivant partirait quand
  /// même.
  int _jeton = 0;

  VoixNotifier(
    this._prefs,
    this._moteur, {
    required AudioPlayer lecteur,
    required VoixNeuraleClient neurale,
    required ConfigIA Function() configIA,
  })  : _lecteur = lecteur,
        _neurale = neurale,
        _configIA = configIA,
        super(const EtatVoix()) {
    _charger();
    _preparer();
  }

  void _charger() {
    try {
      final brut = _prefs.getString(_cleConfigVoix);
      if (brut == null) return;
      state = state.copyWith(
          config: ConfigVoix.fromJson(jsonDecode(brut) as Map<String, dynamic>));
    } catch (_) {
      // Réglage illisible → valeurs par défaut.
    }
  }

  Future<void> _enregistrer() async {
    await _prefs.setString(_cleConfigVoix, jsonEncode(state.config.toJson()));
  }

  Future<void> _preparer() async {
    try {
      // iOS partage sa session audio avec la musique et les appels : sans cela,
      // la lecture reste muette dès qu'autre chose joue.
      if (_estApple) await _moteur.setSharedInstance(true);
      await _moteur.setLanguage('fr-FR');
      await _moteur.awaitSpeakCompletion(true);

      final brutes = await _moteur.getVoices;
      final trouvees = <VoixDisponible>[];
      if (brutes is List) {
        for (final v in brutes) {
          if (v is! Map) continue;
          final nom = v['name']?.toString();
          final locale = v['locale']?.toString();
          if (nom == null || locale == null) continue;
          if (!locale.toLowerCase().startsWith('fr')) continue;
          trouvees.add(VoixDisponible(
              nom: nom, locale: locale, qualite: _noterVoix(nom, locale)));
        }
      }
      trouvees.sort((a, b) => b.qualite.compareTo(a.qualite));

      state = state.copyWith(voixDisponibles: trouvees, pret: true);
      await _appliquerReglages();
    } catch (_) {
      // Pas de moteur de synthèse sur cet appareil : l'assistant reste écrit.
      state = state.copyWith(pret: true, voixDisponibles: const []);
    }
  }

  /// La voix effectivement employée : celle qu'on a choisie si elle est
  /// toujours installée, sinon la mieux notée.
  VoixDisponible? get voixRetenue {
    final dispo = state.voixDisponibles;
    if (dispo.isEmpty) return null;
    final choisie = state.config.voix;
    if (choisie == null) return dispo.first;
    return dispo.firstWhere((v) => v.nom == choisie, orElse: () => dispo.first);
  }

  /// Le débit neutre vaut 0,5 des deux côtés, et non 1.
  ///
  /// iOS attend la constante d'AVSpeechUtterance, qui vaut 0,5. Android semble
  /// attendre 1 — sauf que `flutter_tts` double la valeur avant de la passer au
  /// moteur (`setSpeechRate(rate * 2.0f)`). Envoyer 1 revenait donc à demander
  /// le double de la vitesse naturelle : d'où une voix qui débitait.
  double get _debitPlateforme => (0.5 * state.config.vitesse).clamp(0.1, 1.0);

  Future<void> _appliquerReglages() async {
    final voix = voixRetenue;
    if (voix != null) {
      await _moteur.setVoice(voix.pourMoteur);
      await _moteur.setLanguage(voix.locale);
    }
    await _moteur.setSpeechRate(_debitPlateforme);
    await _moteur.setPitch(state.config.hauteur.clamp(0.5, 2.0));
    await _moteur.setVolume(1.0);
  }

  /// Lit [texte] à voix haute et retient [id] pour que la bulle correspondante
  /// affiche « Arrêter ». Rappuyer sur le message en cours l'interrompt.
  ///
  /// Le moteur neuronal est tenté d'abord s'il est choisi ; son échec, quel
  /// qu'il soit, se règle par la synthèse du téléphone. Un bouton « Écouter »
  /// qui ne produit rien serait pire que pas de bouton du tout.
  Future<void> parler(String id, String texte) async {
    if (state.enLecture == id) {
      await arreter();
      return;
    }
    await arreter();

    final propre = preparerProsodie(nettoyerPourLecture(texte));
    if (propre.isEmpty) return;

    final jeton = ++_jeton;
    state = state.copyWith(enLecture: id, effacerRepli: true);

    try {
      if (state.config.moteur == MoteurVoix.neurale) {
        final motifRepli = await _parlerNeurale(propre, jeton);
        if (_jeton != jeton) return;
        if (motifRepli == null) return; // la voix neuronale a fait le travail
        if (mounted) state = state.copyWith(repliVoix: motifRepli);
      }
      await _parlerAppareil(propre, jeton);
    } catch (_) {
      // Moteur absent ou occupé : on se contente de reprendre le silence.
    } finally {
      if (_jeton == jeton && mounted) {
        state = state.copyWith(effacerLecture: true, prepare: false);
      }
    }
  }

  /// Rend `null` si la voix neuronale a parlé, sinon le motif du repli — dit en
  /// français, parce qu'il s'affiche tel quel dans les réglages.
  Future<String?> _parlerNeurale(String propre, int jeton) async {
    if (mounted) state = state.copyWith(prepare: true);
    try {
      final wav = await _neurale.synthetiser(
        propre,
        _configIA(),
        voix: state.config.voixNeurale,
      );
      if (_jeton != jeton) return null;
      if (mounted) state = state.copyWith(prepare: false);

      // Le débit du réglage s'applique aussi ici : le modèle rend un débit
      // naturel, mais quelqu'un qui l'a réglé plus lent le veut partout.
      await _lecteur.setPlaybackRate(state.config.vitesse.clamp(0.5, 2.0));
      await _lecteur.play(BytesSource(wav, mimeType: 'audio/wav'));

      // `play` rend la main dès le premier échantillon : on attend la fin pour
      // que la bulle cesse d'afficher « Arrêter » au bon moment.
      await _lecteur.onPlayerComplete.first;
      return null;
    } on ErreurVoix catch (e) {
      if (mounted) state = state.copyWith(prepare: false);
      return switch (e.code) {
        CodeErreurVoix.pasDeCle =>
          'Voix naturelle inactive : aucune clé Gemini enregistrée.',
        CodeErreurVoix.auth => 'Voix naturelle inactive : clé Gemini refusée.',
        CodeErreurVoix.quota =>
          'Quota de voix naturelle atteint : lecture par le téléphone.',
        CodeErreurVoix.reseau =>
          'Hors ligne : lecture par la voix du téléphone.',
        CodeErreurVoix.tropLong =>
          'Réponse trop longue pour la voix naturelle : lue par le téléphone.',
        CodeErreurVoix.api => 'Voix naturelle indisponible : ${e.message}',
      };
    } catch (e) {
      if (mounted) state = state.copyWith(prepare: false);
      return 'Voix naturelle indisponible : lecture par le téléphone.';
    }
  }

  Future<void> _parlerAppareil(String propre, int jeton) async {
    await _appliquerReglages();
    final souffles = _respirer(propre);
    for (var i = 0; i < souffles.length; i++) {
      if (_jeton != jeton) return;
      await _moteur.speak(souffles[i].texte);
      if (i < souffles.length - 1 && souffles[i].pause > Duration.zero) {
        await Future<void>.delayed(souffles[i].pause);
      }
    }
  }

  Future<void> arreter() async {
    _jeton++;
    try {
      await _moteur.stop();
    } catch (_) {
      // Rien à arrêter.
    }
    try {
      await _lecteur.stop();
    } catch (_) {
      // Rien à arrêter.
    }
    if (mounted) {
      state = state.copyWith(effacerLecture: true, prepare: false);
    }
  }

  Future<void> activer(bool actif) async {
    if (!actif) await arreter();
    state = state.copyWith(config: state.config.copyWith(active: actif));
    await _enregistrer();
  }

  Future<void> activerLectureAuto(bool actif) async {
    state = state.copyWith(config: state.config.copyWith(lectureAuto: actif));
    await _enregistrer();
  }

  /// Changer de moteur en pleine lecture laisserait deux voix se répondre.
  Future<void> choisirMoteur(MoteurVoix moteur) async {
    await arreter();
    state = state.copyWith(
        config: state.config.copyWith(moteur: moteur), effacerRepli: true);
    await _enregistrer();
  }

  Future<void> choisirVoixNeurale(String id) async {
    await arreter();
    state = state.copyWith(
        config: state.config.copyWith(voixNeurale: id), effacerRepli: true);
    await _enregistrer();
  }

  /// [nom] à `null` pour revenir au choix automatique.
  Future<void> choisirVoix(String? nom) async {
    state = state.copyWith(
        config: state.config
            .copyWith(voix: nom, effacerVoix: nom == null));
    await _enregistrer();
    await _appliquerReglages();
  }

  Future<void> changerVitesse(double vitesse) async {
    state = state.copyWith(
        config: state.config.copyWith(vitesse: vitesse.clamp(0.5, 2.0)));
    await _enregistrer();
  }

  Future<void> changerHauteur(double hauteur) async {
    state = state.copyWith(
        config: state.config.copyWith(hauteur: hauteur.clamp(0.5, 2.0)));
    await _enregistrer();
  }

  /// Fait entendre la voix telle qu'elle est réglée : régler un débit sans
  /// pouvoir l'écouter revient à régler à l'aveugle.
  /// Le texte d'essai porte un montant et une date écrits comme l'assistant les
  /// écrit : c'est là que le débit et la prononciation se jugent.
  Future<void> essayer() => parler(
      '_essai',
      'Bonjour, voici la voix de votre assistant.\n'
          'Le CA du jour s\'élève à 2 450 000 GNF, '
          'soit 12,5 % de plus qu\'hier.\n'
          'Il reste sept sacs de ciment en stock.');

  @override
  void dispose() {
    _moteur.stop();
    _lecteur.dispose();
    super.dispose();
  }
}

/// Un énoncé et le silence qui le suit.
@immutable
class _Souffle {
  final String texte;
  final Duration pause;

  const _Souffle(this.texte, this.pause);
}

/// Découpe le texte comme quelqu'un le dirait : par phrases, avec un temps
/// entre elles et un temps plus long entre deux lignes.
///
/// Le découpage servait jusqu'ici à ne pas dépasser ce que le moteur accepte,
/// et lui laissait tout le reste. Or un moteur lit un paragraphe d'un trait :
/// c'est ce débit sans respiration, plus que le timbre, qui s'entend comme une
/// machine. On ne casse jamais au milieu d'une phrase — une coupure au milieu
/// d'un nombre s'entend aussi.
List<_Souffle> _respirer(String texte) {
  final souffles = <_Souffle>[];
  final lignes =
      texte.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

  for (final ligne in lignes) {
    final tampon = StringBuffer();

    void vider(Duration pause) {
      final t = tampon.toString().trim();
      if (t.isNotEmpty) souffles.add(_Souffle(t, pause));
      tampon.clear();
    }

    // Le deux-points compte : « Total : deux millions » veut son temps d'arrêt.
    for (final phrase in ligne.split(RegExp(r'(?<=[.!?…:])\s+'))) {
      // Une phrase seule plus longue que ce que le moteur accepte : on la coupe
      // telle quelle, faute de meilleur endroit.
      if (phrase.length > _maxParEnonce) {
        vider(_pauseEntrePhrases);
        for (var i = 0; i < phrase.length; i += _maxParEnonce) {
          souffles.add(_Souffle(
              phrase.substring(i, (i + _maxParEnonce).clamp(0, phrase.length)),
              _pauseEntrePhrases));
        }
        continue;
      }
      if (tampon.isNotEmpty &&
          tampon.length + phrase.length + 1 > _cibleSouffle) {
        vider(_pauseEntrePhrases);
      }
      tampon.write(tampon.isEmpty ? phrase : ' $phrase');
    }

    vider(_pauseEntreLignes);
  }

  return souffles;
}

/// Rend prononçable ce qui n'était qu'affichable.
///
/// Le nettoyage Markdown enlève ce qui ne s'entend pas ; il reste ce qui
/// s'entend mal. « 2 450 000 GNF » se lit « deux, quatre cent cinquante, zéro
/// zéro zéro, G N F » : trois nombres et un sigle épelé, là où l'on attend une
/// somme. Une ligne sans point final se dit sur un ton qui reste en l'air.
@visibleForTesting
String preparerProsodie(String texte) {
  var t = texte;

  // Un emoji se prononce : « visage souriant » au milieu d'un bilan.
  t = t.replaceAll(
      RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]',
          unicode: true),
      ' ');

  // Les séparateurs de milliers coupent le nombre en trois. Sans eux, le
  // moteur dit la somme entière.
  // Espace ordinaire, insécable, insécable fine, fine : les quatre s'écrivent
  // pareil à l'écran, et se prononcent tous les quatre.
  t = t.replaceAll(
      RegExp(r'(?<=\d)[\u0020\u00A0\u202F\u2009](?=\d{3}(\D|$))'), '');

  // Sigles et symboles que le moteur épelle.
  t = t.replaceAll(RegExp(r'\bGNF\b'), 'francs guinéens');
  t = t.replaceAll(RegExp(r'\bFG\b'), 'francs guinéens');
  t = t.replaceAll(RegExp(r'\bCA\b'), "chiffre d'affaires");
  t = t.replaceAll(RegExp(r'\bQté\b', caseSensitive: false), 'quantité');
  t = t.replaceAll('%', ' pour cent');
  t = t.replaceAll('€', ' euros');
  t = t.replaceAll(RegExp(r'n°\s*'), 'numéro ');

  // 01/08/2026 s'entend « zéro un slash zéro huit ».
  const mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  t = t.replaceAllMapped(RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b'), (m) {
    final numeroMois = int.parse(m.group(2)!);
    if (numeroMois < 1 || numeroMois > 12) return m.group(0)!;
    return '${int.parse(m.group(1)!)} ${mois[numeroMois - 1]} ${m.group(3)}';
  });

  // Le tiret cadratin ne se marque pas ; la virgule, si.
  t = t.replaceAll(RegExp(r'[ \t][—–][ \t]'), ', ');

  t = t.replaceAll(RegExp(r'[ \t]{2,}'), ' ');

  // Une ligne qui ne finit pas sur une ponctuation se dit sans redescendre :
  // les titres et les puces sonnent alors comme une phrase interrompue.
  return t
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map((l) => RegExp(r'[.!?…:,;]$').hasMatch(l) ? l : '$l.')
      .join('\n');
}

/// Retire du texte tout ce qui se voit mais ne s'entend pas.
///
/// Les réponses de l'assistant sont écrites en Markdown : lues telles quelles,
/// elles donnent « astérisque astérisque marge astérisque astérisque » et des
/// tableaux ânonnés barre par barre. On rend la ponctuation aux tableaux et on
/// efface le balisage.
@visibleForTesting
String nettoyerPourLecture(String markdown) {
  var t = markdown;

  // Les blocs de code se lisent caractère par caractère : on les annonce
  // plutôt que de les infliger.
  t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' (bloc de code) ');
  t = t.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1)!);

  // Images et liens : on garde le libellé, on jette l'adresse.
  t = t.replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!);

  // Un tableau se lit ligne à ligne, les cellules séparées par une virgule.
  // Sa ligne de séparation (|---|---|) ne se lit pas du tout.
  t = t.replaceAll(
      RegExp(r'^[ \t]*\|?[ \t:\-|]+\|[ \t:\-|]*$', multiLine: true), '');
  t = t.replaceAllMapped(RegExp(r'^[ \t]*\|(.+)\|[ \t]*$', multiLine: true),
      (m) {
    final cellules = m
        .group(1)!
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty);
    return '${cellules.join(', ')}.';
  });

  // Titres, listes, citations : le marqueur disparaît, le texte reste.
  // Partout ici, l'espace se dit `[ \t]` et non `\s` : `\s` engloutit les
  // retours à la ligne, et deux lignes soudées se prononcent d'un trait, sans
  // la respiration qui les sépare.
  t = t.replaceAll(RegExp(r'^[ \t]{0,3}#{1,6}[ \t]*', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^[ \t]*>[ \t]?', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^[ \t]*\d+[.)][ \t]+', multiLine: true), '');
  t = t.replaceAll(
      RegExp(r'^[ \t]*([-*_][ \t]?){3,}[ \t]*$', multiLine: true), '');

  // Gras, italique, barré.
  t = t.replaceAll(RegExp(r'\*\*\*|\*\*|\*|__|_|~~'), '');

  // Les espaces devenus superflus, et les lignes vides en série.
  t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
  t = t.replaceAll(RegExp(r'\n{2,}'), '\n');

  return t.trim();
}

// ─── Providers ────────────────────────────────────────────────────────────────

final flutterTtsProvider = Provider<FlutterTts>((ref) => FlutterTts());

final lecteurAudioProvider = Provider<AudioPlayer>((ref) => AudioPlayer());

final voixProvider = StateNotifierProvider<VoixNotifier, EtatVoix>((ref) {
  return VoixNotifier(
    ref.watch(sharedPreferencesProvider),
    ref.watch(flutterTtsProvider),
    lecteur: ref.watch(lecteurAudioProvider),
    neurale: ref.watch(voixNeuraleClientProvider),
    // `read` et non `watch` : la voix n'a pas à se reconstruire — et donc à se
    // taire — parce qu'on vient de saisir une clé dans un autre écran.
    configIA: () => ref.read(configIAProvider),
  );
});
