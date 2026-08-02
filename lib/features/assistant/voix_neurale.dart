import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_config.dart';

// ─── Voix neuronale (Gemini TTS) ──────────────────────────────────────────────
// La synthèse du téléphone ne coûte rien et fonctionne hors ligne : c'est le
// recours, et il le restera. Mais elle s'entend pour ce qu'elle est. Une analyse
// de trésorerie lue par le moteur d'Android sonne comme un distributeur de
// billets — le commerçant l'écoute une fois, puis rallume l'écran.
//
// Gemini sait rendre la même phrase avec une voix qu'on ne distingue pas d'une
// personne : intonation, respiration, accentuation du chiffre qui compte. Elle
// passe par la clé Gemini déjà saisie pour l'assistant — rien de plus à
// configurer — et on peut lui *dire* comment parler, ce qu'aucun moteur
// embarqué ne permet.
//
// Trois précautions, parce qu'une voix en ligne est une voix qui peut se taire :
//   • tout échec bascule sur la synthèse du téléphone, sans le dire deux fois ;
//   • l'audio déjà payé est gardé en mémoire : réécouter une réponse ne
//     redemande rien ;
//   • le texte est plafonné. Faire lire dix mille caractères par une voix
//     facturée au caractère est une facture, pas une fonctionnalité.

/// Le modèle de synthèse. Distinct des modèles de conversation, et doté de son
/// propre quota : la voix continue de fonctionner même quand le modèle de
/// discussion est à sec pour la journée.
const String _modeleTts = 'gemini-2.5-flash-preview-tts';

/// Au-delà, on renonce à la voix neuronale et on laisse le téléphone lire.
/// Un rapport de trente mille caractères ne s'écoute de toute façon pas.
const int _maxCaracteres = 4000;

/// Nombre d'énoncés gardés en mémoire. Une dizaine couvre la conversation en
/// cours sans faire enfler l'application.
const int _taillleCache = 12;

/// Une voix Gemini, avec ce qu'elle donne à entendre.
///
/// Les noms viennent du catalogue Google ; le libellé, lui, doit se choisir
/// dans une liste par quelqu'un qui n'a jamais lu ce catalogue.
@immutable
class VoixNeurale {
  final String id;
  final String libelle;
  final String description;
  const VoixNeurale(this.id, this.libelle, this.description);
}

/// La sélection retenue : les voix les plus justes en français, des deux
/// timbres, plutôt que les trente du catalogue dont la moitié sonne anglaise.
const List<VoixNeurale> kVoixNeurales = [
  VoixNeurale('Kore', 'Kore — posée',
      'Féminine, claire et assurée. Le meilleur choix pour des chiffres.'),
  VoixNeurale('Charon', 'Charon — grave',
      'Masculine, calme et posée. Se suit bien dans le bruit du magasin.'),
  VoixNeurale('Aoede', 'Aoede — chaleureuse',
      'Féminine, souple et vivante.'),
  VoixNeurale('Puck', 'Puck — enjouée',
      'Masculine, rythmée et enlevée.'),
  VoixNeurale('Zephyr', 'Zephyr — lumineuse', 'Féminine, claire et légère.'),
  VoixNeurale('Orus', 'Orus — ferme', 'Masculine, nette et directe.'),
  VoixNeurale('Leda', 'Leda — jeune', 'Féminine, souple et naturelle.'),
  VoixNeurale('Enceladus', 'Enceladus — feutrée',
      'Masculine, douce, presque chuchotée.'),
];

const String kVoixNeuraleParDefaut = 'Kore';

/// La consigne de jeu donnée au modèle avant le texte.
///
/// C'est ce qui sépare une lecture d'une parole. Sans elle, la voix ânonne les
/// montants ; avec, elle les pose. On lui dit aussi de ne rien ajouter : un
/// modèle de synthèse qui commente ce qu'il lit est un modèle qui invente.
String consigneDeLecture(String texte) =>
    'Lis le texte suivant à voix haute en français, avec le ton posé et '
    'chaleureux d\'un collaborateur qui rend compte de la journée à son '
    'patron. Détache les montants et les quantités pour qu\'ils s\'entendent '
    'bien, marque une respiration entre les phrases, et garde un débit '
    'tranquille. Ne commente pas, n\'ajoute rien, ne lis aucune consigne : '
    'prononce uniquement le texte.\n\n$texte';

enum CodeErreurVoix { pasDeCle, auth, quota, reseau, tropLong, api }

class ErreurVoix implements Exception {
  final String message;
  final CodeErreurVoix code;
  ErreurVoix(this.message, [this.code = CodeErreurVoix.api]);

  @override
  String toString() => message;
}

class VoixNeuraleClient {
  final Dio _dio;

  /// Énoncés déjà payés, indexés par (voix + texte).
  final Map<String, Uint8List> _cache = {};
  final List<String> _ordre = [];

  VoixNeuraleClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 90),
            ));

  /// Rend un WAV jouable, prêt à être passé au lecteur audio.
  ///
  /// [texte] doit déjà être nettoyé de son balisage : on ne fait pas prononcer
  /// des astérisques à une voix qu'on paie.
  Future<Uint8List> synthetiser(
    String texte,
    ConfigIA cfg, {
    String voix = kVoixNeuraleParDefaut,
    CancelToken? annulation,
  }) async {
    final propre = texte.trim();
    if (propre.isEmpty) {
      throw ErreurVoix('Rien à lire.', CodeErreurVoix.api);
    }
    if (propre.length > _maxCaracteres) {
      throw ErreurVoix(
          'Texte trop long pour la voix neuronale.', CodeErreurVoix.tropLong);
    }

    // La voix se paie sur la clé Gemini, quel que soit le fournisseur choisi
    // pour la conversation : un commerçant sous Claude garde donc sa belle voix
    // s'il a renseigné les deux clés.
    final cle = (cfg.cles[FournisseurIA.gemini] ?? '')
        .split(RegExp(r'[\s,;]+'))
        .map((c) => c.trim())
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');
    if (cle.isEmpty) {
      throw ErreurVoix(
          'Aucune clé Gemini : la voix neuronale a besoin de la même clé que '
          'l\'assistant.',
          CodeErreurVoix.pasDeCle);
    }

    final cleCache = '$voix|$propre';
    final memorise = _cache[cleCache];
    if (memorise != null) return memorise;

    final Response reponse;
    try {
      reponse = await _dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$_modeleTts:generateContent',
        cancelToken: annulation,
        options: Options(
          headers: {'content-type': 'application/json', 'x-goog-api-key': cle},
          validateStatus: (_) => true,
        ),
        data: {
          'contents': [
            {
              'parts': [
                {'text': consigneDeLecture(propre)}
              ]
            }
          ],
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': voix},
              },
            },
          },
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ErreurVoix(
          'Voix neuronale injoignable.', CodeErreurVoix.reseau);
    }

    final statut = reponse.statusCode ?? 0;
    if (statut != 200) {
      final donnees = reponse.data;
      final message = donnees is Map && donnees['error'] is Map
          ? donnees['error']['message']?.toString() ?? 'Erreur $statut'
          : 'Erreur $statut';
      throw ErreurVoix(
        message,
        switch (statut) {
          401 || 403 => CodeErreurVoix.auth,
          429 => CodeErreurVoix.quota,
          _ => CodeErreurVoix.api,
        },
      );
    }

    final parts =
        reponse.data['candidates']?[0]?['content']?['parts'] as List?;
    final inline = parts
        ?.whereType<Map>()
        .map((p) => p['inlineData'])
        .whereType<Map>()
        .firstOrNull;
    final b64 = inline?['data']?.toString();
    if (b64 == null || b64.isEmpty) {
      throw ErreurVoix('La voix n\'a rendu aucun son.', CodeErreurVoix.api);
    }

    // Gemini rend du PCM brut (« audio/L16;codec=pcm;rate=24000 ») : aucun
    // lecteur ne sait le jouer tel quel. On lui pose l'en-tête WAV qui lui
    // manque, ce qui coûte quarante-quatre octets et évite un décodeur.
    final pcm = base64Decode(b64);
    final wav = enveloppeWav(pcm,
        frequence: _frequenceDe(inline?['mimeType']?.toString()));

    _cache[cleCache] = wav;
    _ordre.add(cleCache);
    while (_ordre.length > _taillleCache) {
      _cache.remove(_ordre.removeAt(0));
    }
    return wav;
  }

  /// La fréquence annoncée dans le type MIME, 24 kHz par défaut — c'est ce que
  /// rend le modèle aujourd'hui, mais l'annonce fait foi.
  static int _frequenceDe(String? mime) {
    final m = RegExp(r'rate=(\d+)').firstMatch(mime ?? '');
    return int.tryParse(m?.group(1) ?? '') ?? 24000;
  }

  void viderCache() {
    _cache.clear();
    _ordre.clear();
  }
}

/// Pose l'en-tête WAV canonique (44 octets) devant du PCM 16 bits signé.
///
/// Isolé et testable : une erreur d'un octet ici rend un fichier que le lecteur
/// refuse, et le symptôme — « la voix ne marche pas » — ne dit rien de la cause.
@visibleForTesting
Uint8List enveloppeWav(
  Uint8List pcm, {
  int frequence = 24000,
  int canaux = 1,
  int bitsParEchantillon = 16,
}) {
  final octetsParBloc = canaux * bitsParEchantillon ~/ 8;
  final debitOctets = frequence * octetsParBloc;

  final entete = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      entete.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  entete.setUint32(4, 36 + pcm.length, Endian.little); // taille du fichier − 8
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  entete.setUint32(16, 16, Endian.little); // taille du bloc fmt
  entete.setUint16(20, 1, Endian.little); // 1 = PCM non compressé
  entete.setUint16(22, canaux, Endian.little);
  entete.setUint32(24, frequence, Endian.little);
  entete.setUint32(28, debitOctets, Endian.little);
  entete.setUint16(32, octetsParBloc, Endian.little);
  entete.setUint16(34, bitsParEchantillon, Endian.little);
  ascii(36, 'data');
  entete.setUint32(40, pcm.length, Endian.little);

  return Uint8List(44 + pcm.length)
    ..setRange(0, 44, entete.buffer.asUint8List())
    ..setRange(44, 44 + pcm.length, pcm);
}

final voixNeuraleClientProvider =
    Provider<VoixNeuraleClient>((ref) => VoixNeuraleClient());
