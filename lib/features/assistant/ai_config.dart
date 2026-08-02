import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme.dart' show sharedPreferencesProvider;

// ─── Configuration de l'assistant ─────────────────────────────────────────────
// Transposition de `src/lib/ai.ts` de l'application web. Les deux applications
// proposent les mêmes fournisseurs et les mêmes modèles : un gérant qui règle
// l'assistant sur son ordinateur doit retrouver les mêmes choix sur son
// téléphone.

enum FournisseurIA { claude, gemini }

class ModeleIA {
  final String id;
  final String libelle;
  final String? note;
  const ModeleIA(this.id, this.libelle, [this.note]);
}

class InfoFournisseur {
  final FournisseurIA id;
  final String nom;
  final String editeur;
  final List<ModeleIA> modeles;
  final String modeleParDefaut;
  final String exempleCle;
  final String aideCle;
  final String urlCle;

  const InfoFournisseur({
    required this.id,
    required this.nom,
    required this.editeur,
    required this.modeles,
    required this.modeleParDefaut,
    required this.exempleCle,
    required this.aideCle,
    required this.urlCle,
  });
}

const Map<FournisseurIA, InfoFournisseur> kFournisseurs = {
  FournisseurIA.claude: InfoFournisseur(
    id: FournisseurIA.claude,
    nom: 'Claude',
    editeur: 'Anthropic',
    modeles: [
      ModeleIA('claude-sonnet-5', 'Claude Sonnet 5',
          'Recommandé, performant et équilibré'),
      ModeleIA('claude-opus-4-8', 'Claude Opus 4.8',
          'Analyse financière la plus poussée'),
      ModeleIA('claude-haiku-4-5', 'Claude Haiku 4.5', 'Rapide et économique'),
    ],
    modeleParDefaut: 'claude-sonnet-5',
    exempleCle: 'sk-ant-…',
    aideCle: 'Créez une clé API dans la console Anthropic.',
    urlCle: 'https://console.anthropic.com/settings/keys',
  ),
  FournisseurIA.gemini: InfoFournisseur(
    id: FournisseurIA.gemini,
    nom: 'Gemini',
    editeur: 'Google',
    // Le palier gratuit se compte en requêtes par jour et par modèle : les
    // modèles « flash » de dernière génération n'en accordent qu'une vingtaine,
    // les « flash-lite » beaucoup plus. On met donc les lite en tête.
    modeles: [
      ModeleIA('gemini-flash-lite-latest', 'Gemini Flash Lite',
          'Recommandé — le quota gratuit le plus large'),
      ModeleIA('gemini-3.5-flash-lite', 'Gemini 3.5 Flash Lite',
          'Version figée, quota confortable'),
      ModeleIA('gemini-flash-latest', 'Gemini Flash',
          'Plus fin, mais ~20 requêtes/jour en gratuit'),
      ModeleIA('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Génération précédente'),
      ModeleIA('gemini-pro-latest', 'Gemini Pro',
          'Le plus précis — nécessite un compte payant'),
    ],
    modeleParDefaut: 'gemini-flash-lite-latest',
    exempleCle: 'AIza… ou AQ.… (les deux formats fonctionnent)',
    aideCle: 'Obtenez une clé API gratuite dans Google AI Studio.',
    urlCle: 'https://aistudio.google.com/apikey',
  ),
};

/// Relais serveur. Renseigné, les appels y passent et les clés restent côté
/// serveur ; vide, on retombe sur les clés saisies dans les paramètres.
const String kRelaisIA = String.fromEnvironment('AI_PROXY_URL', defaultValue: '');

class ConfigIA {
  final FournisseurIA fournisseur;
  final String modele;
  final Map<FournisseurIA, String> cles;

  /// Autorise l'assistant à consulter le web (cours des matériaux,
  /// fournisseurs, taux de change). Sans cela il ne connaît que les données du
  /// magasin et sa mémoire d'entraînement, forcément périmée sur les prix.
  final bool recherche;

  /// Clé SerpAPI. L'application web garde la sienne sur son serveur — un
  /// navigateur ne peut pas appeler SerpAPI. Le téléphone, si : la clé se saisit
  /// donc ici, et la recherche fonctionne sans qu'un serveur soit déployé.
  final String cleSerpapi;

  const ConfigIA({
    this.fournisseur = FournisseurIA.gemini,
    this.modele = 'gemini-flash-lite-latest',
    this.cles = const {},
    this.recherche = true,
    this.cleSerpapi = '',
  });

  /// La recherche est demandée *et* possible. Sans clé ni relais, l'annoncer au
  /// modèle reviendrait à lui promettre un outil qui répond toujours « non ».
  bool get rechercheDisponible =>
      recherche && (relaisActif || cleSerpapi.trim().isNotEmpty);

  InfoFournisseur get info => kFournisseurs[fournisseur]!;

  /// Le champ « clé » accepte plusieurs clés séparées par une virgule ou un
  /// retour à la ligne. On les essaie tour à tour : une clé épuisée laisse sa
  /// place à la suivante au lieu de bloquer l'assistant.
  List<String> get listeCles => (cles[fournisseur] ?? '')
      .split(RegExp(r'[\s,;]+'))
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();

  bool get relaisActif => kRelaisIA.isNotEmpty;

  /// L'assistant est utilisable : soit par le relais, soit avec une clé.
  bool get utilisable => relaisActif || listeCles.isNotEmpty;

  ConfigIA copyWith({
    FournisseurIA? fournisseur,
    String? modele,
    Map<FournisseurIA, String>? cles,
    bool? recherche,
    String? cleSerpapi,
  }) =>
      ConfigIA(
        fournisseur: fournisseur ?? this.fournisseur,
        modele: modele ?? this.modele,
        cles: cles ?? this.cles,
        recherche: recherche ?? this.recherche,
        cleSerpapi: cleSerpapi ?? this.cleSerpapi,
      );

  Map<String, dynamic> toJson() => {
        'fournisseur': fournisseur.name,
        'modele': modele,
        'cles': {for (final e in cles.entries) e.key.name: e.value},
        'recherche': recherche,
        'cleSerpapi': cleSerpapi,
      };

  /// Relit la configuration en se méfiant de son contenu : un modèle retiré du
  /// catalogue, un fournisseur inconnu ou un fichier corrompu ne doivent pas
  /// rendre l'assistant inutilisable.
  factory ConfigIA.fromJson(Map<String, dynamic> json) {
    final fournisseur = FournisseurIA.values.firstWhere(
      (f) => f.name == json['fournisseur'],
      orElse: () => FournisseurIA.gemini,
    );
    final info = kFournisseurs[fournisseur]!;
    final modele = json['modele'] as String?;
    final clesBrutes = json['cles'];

    return ConfigIA(
      fournisseur: fournisseur,
      modele: info.modeles.any((m) => m.id == modele)
          ? modele!
          : info.modeleParDefaut,
      cles: clesBrutes is Map
          ? {
              for (final f in FournisseurIA.values)
                f: (clesBrutes[f.name] as String?) ?? '',
            }
          : const {},
      recherche: json['recherche'] != false,
      cleSerpapi: (json['cleSerpapi'] as String?)?.trim() ?? '',
    );
  }
}

const _cleConfig = 'ai_config';

class ConfigIANotifier extends StateNotifier<ConfigIA> {
  final SharedPreferences _prefs;

  ConfigIANotifier(this._prefs) : super(const ConfigIA()) {
    _charger();
  }

  void _charger() {
    try {
      final brut = _prefs.getString(_cleConfig);
      if (brut == null) return;
      state = ConfigIA.fromJson(jsonDecode(brut) as Map<String, dynamic>);
    } catch (_) {
      // Configuration illisible → valeurs par défaut.
    }
  }

  Future<void> _enregistrer() async {
    await _prefs.setString(_cleConfig, jsonEncode(state.toJson()));
  }

  Future<void> changerFournisseur(FournisseurIA fournisseur) async {
    // Le modèle appartient au fournisseur : en changer sans réinitialiser le
    // modèle enverrait un identifiant Gemini à Claude.
    state = state.copyWith(
        fournisseur: fournisseur,
        modele: kFournisseurs[fournisseur]!.modeleParDefaut);
    await _enregistrer();
  }

  Future<void> changerModele(String modele) async {
    state = state.copyWith(modele: modele);
    await _enregistrer();
  }

  Future<void> definirCle(FournisseurIA fournisseur, String cle) async {
    state = state.copyWith(cles: {...state.cles, fournisseur: cle.trim()});
    await _enregistrer();
  }

  Future<void> definirCleSerpapi(String cle) async {
    state = state.copyWith(cleSerpapi: cle.trim());
    await _enregistrer();
  }

  Future<void> activerRecherche(bool actif) async {
    state = state.copyWith(recherche: actif);
    await _enregistrer();
  }
}

final configIAProvider =
    StateNotifierProvider<ConfigIANotifier, ConfigIA>((ref) {
  return ConfigIANotifier(ref.watch(sharedPreferencesProvider));
});
