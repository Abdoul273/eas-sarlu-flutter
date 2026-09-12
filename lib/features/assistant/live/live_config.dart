import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart' show sharedPreferencesProvider;

// ─── Le mode vocal : modèles, voix, réglages ──────────────────────────────────
// Transposition du « système » d'ANO-GPT : un modèle Live principal, un modèle
// de repli quand le premier n'est plus servi, une voix prédéfinie, et rien
// d'écrit en dur ailleurs. Monter de version se fait ici, une fois.

/// Le modèle de conversation en direct. Audio natif : il entend et parle
/// lui-même, sans passer par une transcription intermédiaire.
const String kModeleLivePrincipal = 'models/gemini-3.1-flash-live-preview';

/// Quand le principal n'existe plus (aperçu retiré) ou refuse la session
/// bidirectionnelle, on retombe ici sans que le commerçant ait à choisir.
const String kModeleLiveRepli = 'models/gemini-2.5-flash-native-audio-latest';

/// Marqueurs d'un refus DU MODÈLE — et non de la clé, ni du réseau. Seuls
/// ceux-là justifient de basculer sur le repli.
const List<String> _marqueursModele = [
  'model not found',
  'model is not found',
  'not supported for bidirectional',
  'not supported for live',
  'unsupported model',
  'unknown model',
  'requested entity was not found',
];

bool erreurDeModele(Object erreur) {
  final m = erreur.toString().toLowerCase().split(RegExp(r'\s+')).join(' ');
  return _marqueursModele.any(m.contains);
}

/// Marqueurs d'une clé refusée. Le code WebSocket 1007 seul ne signifie PAS
/// clé invalide : Gemini l'emploie aussi pour un champ de configuration
/// inconnu. C'est le texte qui tranche.
const List<String> _marqueursCle = [
  'api key not valid',
  'api_key_invalid',
  'invalid api key',
  'api key expired',
  'permission_denied',
  'permission denied',
];

bool erreurDeCle(Object erreur) {
  final m = erreur.toString().toLowerCase();
  return _marqueursCle.any(m.contains);
}

/// Une voix prédéfinie de Gemini Live.
@immutable
class VoixLive {
  final String id;
  final String qualificatif;
  const VoixLive(this.id, this.qualificatif);

  String get libelle => '$id — $qualificatif';
}

/// Les voix acceptées par `prebuiltVoiceConfig`. Le qualificatif ne sert qu'à
/// l'écran ; seul le nom part à Gemini.
const List<VoixLive> kVoixLive = [
  VoixLive('Kore', 'ferme'),
  VoixLive('Charon', 'informative'),
  VoixLive('Aoede', 'légère'),
  VoixLive('Sulafat', 'chaleureuse'),
  VoixLive('Achird', 'amicale'),
  VoixLive('Gacrux', 'mature'),
  VoixLive('Iapetus', 'claire'),
  VoixLive('Vindemiatrix', 'douce'),
  VoixLive('Algieba', 'fluide'),
  VoixLive('Schedar', 'équilibrée'),
  VoixLive('Puck', 'enjouée'),
  VoixLive('Fenrir', 'enthousiaste'),
  VoixLive('Zephyr', 'lumineuse'),
  VoixLive('Leda', 'jeune'),
  VoixLive('Orus', 'ferme'),
  VoixLive('Algenib', 'grave'),
];

const String kVoixLiveParDefaut = 'Kore';

String normaliserVoixLive(String? v) {
  final voulu = (v ?? '').trim().toLowerCase();
  for (final voix in kVoixLive) {
    if (voix.id.toLowerCase() == voulu) return voix.id;
  }
  return kVoixLiveParDefaut;
}

/// Ce que le commerçant règle pour le mode vocal.
@immutable
class ConfigLive {
  final String voix;

  /// Les sous-titres de ce qui se dit, affichés pendant la conversation.
  final bool sousTitres;

  /// Le téléphone vibre brièvement quand l'assistant commence à parler.
  final bool retourHaptique;

  /// Ce qui a été dit en vocal est versé dans l'historique de la discussion.
  final bool journaliser;

  const ConfigLive({
    this.voix = kVoixLiveParDefaut,
    this.sousTitres = true,
    this.retourHaptique = true,
    this.journaliser = true,
  });

  ConfigLive copyWith({
    String? voix,
    bool? sousTitres,
    bool? retourHaptique,
    bool? journaliser,
  }) =>
      ConfigLive(
        voix: voix ?? this.voix,
        sousTitres: sousTitres ?? this.sousTitres,
        retourHaptique: retourHaptique ?? this.retourHaptique,
        journaliser: journaliser ?? this.journaliser,
      );

  Map<String, dynamic> toJson() => {
        'voix': voix,
        'sousTitres': sousTitres,
        'retourHaptique': retourHaptique,
        'journaliser': journaliser,
      };

  factory ConfigLive.fromJson(Map<String, dynamic> j) => ConfigLive(
        voix: normaliserVoixLive(j['voix'] as String?),
        sousTitres: j['sousTitres'] != false,
        retourHaptique: j['retourHaptique'] != false,
        journaliser: j['journaliser'] != false,
      );
}

const _cle = 'live_config';

class ConfigLiveNotifier extends StateNotifier<ConfigLive> {
  final SharedPreferences _prefs;

  ConfigLiveNotifier(this._prefs) : super(const ConfigLive()) {
    try {
      final brut = _prefs.getString(_cle);
      if (brut != null) {
        state = ConfigLive.fromJson(jsonDecode(brut) as Map<String, dynamic>);
      }
    } catch (_) {
      // Réglages illisibles → valeurs par défaut.
    }
  }

  Future<void> _enregistrer() =>
      _prefs.setString(_cle, jsonEncode(state.toJson()));

  Future<void> choisirVoix(String id) async {
    state = state.copyWith(voix: normaliserVoixLive(id));
    await _enregistrer();
  }

  Future<void> activerSousTitres(bool v) async {
    state = state.copyWith(sousTitres: v);
    await _enregistrer();
  }

  Future<void> activerHaptique(bool v) async {
    state = state.copyWith(retourHaptique: v);
    await _enregistrer();
  }

  Future<void> activerJournal(bool v) async {
    state = state.copyWith(journaliser: v);
    await _enregistrer();
  }
}

final configLiveProvider =
    StateNotifierProvider<ConfigLiveNotifier, ConfigLive>(
  (ref) => ConfigLiveNotifier(ref.watch(sharedPreferencesProvider)),
);
