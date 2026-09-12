import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'live_config.dart';

// ─── La session Gemini Live ───────────────────────────────────────────────────
// Une WebSocket bidirectionnelle : le micro part en PCM 16 kHz, la voix revient
// en PCM 24 kHz, et le serveur décide lui-même où commencent et finissent les
// tours (VAD serveur). Le modèle peut appeler les outils du magasin en pleine
// phrase ; la réponse lui revient sur la même connexion.
//
// Ce fichier ne sait rien de l'audio ni de l'écran. Il parle le protocole,
// et raconte ce qui se passe par un flux d'évènements.

/// Ce que le serveur nous raconte.
sealed class EvenementLive {
  const EvenementLive();
}

/// La session est ouverte et configurée : on peut envoyer le micro.
class LivePret extends EvenementLive {
  final String modele;
  const LivePret(this.modele);
}

/// Un bloc de voix, PCM 16 bits mono 24 kHz.
class LiveAudio extends EvenementLive {
  final Uint8List pcm;
  const LiveAudio(this.pcm);
}

/// Ce que l'utilisateur a dit, tel que Gemini l'a entendu.
class LiveTranscriptionEntree extends EvenementLive {
  final String texte;
  const LiveTranscriptionEntree(this.texte);
}

/// Ce que l'assistant dit, au fil de la voix.
class LiveTranscriptionSortie extends EvenementLive {
  final String texte;
  const LiveTranscriptionSortie(this.texte);
}

/// L'utilisateur a coupé la parole : tout ce qui est en attente de lecture
/// doit être jeté.
class LiveInterrompu extends EvenementLive {
  const LiveInterrompu();
}

/// Le modèle a fini son tour.
class LiveTourTermine extends EvenementLive {
  const LiveTourTermine();
}

/// Le modèle demande des outils. La réponse passe par [LiveSession.repondreOutils].
class LiveAppelOutils extends EvenementLive {
  final List<AppelFonction> appels;
  const LiveAppelOutils(this.appels);
}

/// Le serveur ferme bientôt : la coupure qui suit est prévue, pas subie.
class LiveFermetureAnnoncee extends EvenementLive {
  const LiveFermetureAnnoncee();
}

/// La connexion est tombée. [reprisePossible] : on a une poignée valide.
class LiveDeconnecte extends EvenementLive {
  final Object? erreur;
  const LiveDeconnecte(this.erreur);
}

@immutable
class AppelFonction {
  final String id;
  final String nom;
  final Map<String, dynamic> args;
  const AppelFonction(this.id, this.nom, this.args);
}

/// Une déclaration d'outil au format Gemini.
Map<String, dynamic> declarationFonction({
  required String nom,
  required String description,
  Map<String, String> parametres = const {},
  List<String> requis = const [],
}) =>
    {
      'name': nom,
      'description': description,
      if (parametres.isNotEmpty)
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            for (final e in parametres.entries)
              e.key: {'type': 'STRING', 'description': e.value},
          },
          if (requis.isNotEmpty) 'required': requis,
        },
    };

class ErreurLive implements Exception {
  final String message;
  const ErreurLive(this.message);
  @override
  String toString() => message;
}

/// Ce qu'il faut savoir entre deux connexions.
///
/// * la **poignée de reprise** : Gemini en envoie une régulièrement ; renvoyée
///   à la connexion suivante, elle redonne la conversation là où elle s'est
///   arrêtée. Sans elle, chaque coupure repart d'un modèle amnésique ;
/// * le **rythme des tentatives** : 1, 2, 4, 8, 16, 30, 30… secondes. Une
///   coupure annoncée par le serveur se rattrape tout de suite ;
/// * ce que l'écran doit dire : une coupure de trois secondes se traverse sans
///   un mot. Seule une vraie absence se raconte.
class EtatConnexion {
  static const premierDelai = Duration(seconds: 1);
  static const delaiMax = Duration(seconds: 30);

  /// Au-delà, le serveur a oublié la session : renvoyer la poignée coûte un
  /// aller-retour et un refus.
  static const dureeVieHandle = Duration(minutes: 15);

  /// En dessous, personne n'a rien remarqué : on se tait.
  static const coupureSilencieuse = Duration(seconds: 12);

  /// Au-delà, c'est une autre conversation.
  static const conversationPerdue = Duration(minutes: 3);

  String? _handle;
  DateTime? _handleA;
  int _tentatives = 0;
  DateTime? _tombeeA;
  bool _aEteConnecte = false;
  bool fermeturePrevue = false;

  void surConnexion() {
    _tentatives = 0;
    _tombeeA = null;
    _aEteConnecte = true;
    fermeturePrevue = false;
  }

  void surHandle(String? h) {
    if (h != null && h.isNotEmpty) {
      _handle = h;
      _handleA = DateTime.now();
    }
  }

  void surDeconnexion() {
    _tombeeA ??= DateTime.now();
    _tentatives++;
  }

  void oublierSession() {
    _handle = null;
    _handleA = null;
  }

  String? get handle {
    final h = _handle;
    final a = _handleA;
    if (h == null || a == null) return null;
    if (DateTime.now().difference(a) > dureeVieHandle) {
      oublierSession();
      return null;
    }
    return h;
  }

  Duration get prochainDelai {
    if (fermeturePrevue) return Duration.zero;
    if (_tentatives <= 1) return premierDelai;
    final s = premierDelai.inSeconds * (1 << (_tentatives - 1));
    return s >= delaiMax.inSeconds ? delaiMax : Duration(seconds: s);
  }

  Duration get dureeCoupure =>
      _tombeeA == null ? Duration.zero : DateTime.now().difference(_tombeeA!);

  bool get coupureVisible =>
      _aEteConnecte && !fermeturePrevue && dureeCoupure >= coupureSilencieuse;

  bool get conversationEstPerdue =>
      handle == null || dureeCoupure >= conversationPerdue;
}

/// Une connexion Live. À usage unique : on en ouvre une nouvelle à chaque
/// reprise, l'[EtatConnexion] porte ce qui doit survivre entre les deux.
class LiveSession {
  static const _hote = 'generativelanguage.googleapis.com';
  static const _chemin =
      '/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  final String cle;
  final String modele;
  final String voix;
  final String instructionSysteme;
  final List<Map<String, dynamic>> outils;
  final String? handleReprise;

  WebSocketChannel? _canal;
  StreamSubscription? _abonnement;
  final _evenements = StreamController<EvenementLive>.broadcast();
  final _pret = Completer<void>();
  bool _fermee = false;

  LiveSession({
    required this.cle,
    required this.modele,
    required this.voix,
    required this.instructionSysteme,
    required this.outils,
    this.handleReprise,
  });

  Stream<EvenementLive> get evenements => _evenements.stream;
  bool get ouverte => !_fermee && _canal != null;

  /// Ouvre la WebSocket et envoie la configuration. Rend la main quand le
  /// serveur a répondu `setupComplete` — ou lève s'il a refusé.
  Future<void> ouvrir() async {
    final uri = Uri(
      scheme: 'wss',
      host: _hote,
      path: _chemin,
      queryParameters: {'key': cle},
    );
    final canal = WebSocketChannel.connect(uri);
    _canal = canal;

    try {
      await canal.ready;
    } catch (e) {
      throw ErreurLive('Connexion impossible : $e');
    }

    _abonnement = canal.stream.listen(
      _surMessage,
      onError: (Object e) => _terminer(e),
      onDone: () => _terminer(null),
      cancelOnError: true,
    );

    _envoyer({
      'setup': {
        'model': modele,
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          // Basse : une commande vocale demande de la fidélité, pas de
          // l'invention — surtout avec des chiffres.
          'temperature': 0.35,
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voix},
            },
            'languageCode': 'fr-FR',
          },
        },
        'systemInstruction': {
          'parts': [
            {'text': instructionSysteme}
          ],
        },
        if (outils.isNotEmpty)
          'tools': [
            {'functionDeclarations': outils}
          ],
        // Les sous-titres des deux côtés : ce que Gemini a entendu, et ce qu'il
        // dit. C'est aussi ce qui est versé dans l'historique après coup.
        'inputAudioTranscription': {},
        'outputAudioTranscription': {},
        // La poignée du tour précédent : renvoyée, Gemini reprend au lieu de
        // repartir de zéro.
        'sessionResumption': {
          if (handleReprise != null) 'handle': handleReprise,
        },
        // Une conversation longue ne meurt pas quand sa fenêtre se remplit :
        // le serveur résume l'ancien en gardant la session et ses outils.
        'contextWindowCompression': {'slidingWindow': {}},
      },
    });

    // Un serveur qui ne répond jamais « prêt » ne doit pas bloquer l'écran.
    await _pret.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        fermer();
        throw const ErreurLive('Gemini ne répond pas.');
      },
    );
  }

  /// Un bloc de micro, PCM 16 bits mono 16 kHz.
  void envoyerAudio(Uint8List pcm) {
    if (!ouverte) return;
    _envoyer({
      'realtimeInput': {
        'audio': {
          'data': base64Encode(pcm),
          'mimeType': 'audio/pcm;rate=16000',
        },
      },
    });
  }

  /// Un message tapé au clavier, ou une information injectée par
  /// l'application (« l'utilisateur a confirmé l'action »).
  void envoyerTexte(String texte, {bool finDeTour = true}) {
    if (!ouverte) return;
    _envoyer({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': texte}
            ],
          }
        ],
        'turnComplete': finDeTour,
      },
    });
  }

  /// Rend au modèle les résultats des outils qu'il a demandés.
  void repondreOutils(Map<AppelFonction, String> resultats) {
    if (!ouverte || resultats.isEmpty) return;
    _envoyer({
      'toolResponse': {
        'functionResponses': [
          for (final e in resultats.entries)
            {
              'id': e.key.id,
              'name': e.key.nom,
              'response': {'result': e.value},
            },
        ],
      },
    });
  }

  void _envoyer(Map<String, dynamic> message) {
    try {
      _canal?.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('Live : envoi refusé : $e');
    }
  }

  void _surMessage(dynamic brut) {
    // Le serveur alterne trames texte et trames binaires pour le même JSON.
    final String texte;
    if (brut is String) {
      texte = brut;
    } else if (brut is List<int>) {
      texte = utf8.decode(brut);
    } else {
      return;
    }

    final Map<String, dynamic> m;
    try {
      final d = jsonDecode(texte);
      if (d is! Map<String, dynamic>) return;
      m = d;
    } catch (_) {
      return;
    }

    if (m.containsKey('setupComplete')) {
      if (!_pret.isCompleted) _pret.complete();
      _evenements.add(LivePret(modele));
      return;
    }

    if (m.containsKey('error')) {
      final err = m['error'];
      final msg = err is Map ? (err['message'] ?? err).toString() : '$err';
      if (!_pret.isCompleted) _pret.completeError(ErreurLive(msg));
      _terminer(ErreurLive(msg));
      return;
    }

    final reprise = m['sessionResumptionUpdate'];
    if (reprise is Map && reprise['resumable'] == true) {
      final h = reprise['newHandle'];
      if (h is String) _evenements.add(NouveauHandleLive(h));
    }

    if (m.containsKey('goAway')) {
      _evenements.add(const LiveFermetureAnnoncee());
    }

    final contenu = m['serverContent'];
    if (contenu is Map) {
      if (contenu['interrupted'] == true) {
        _evenements.add(const LiveInterrompu());
      }
      final entree = contenu['inputTranscription'];
      if (entree is Map && entree['text'] is String) {
        _evenements.add(LiveTranscriptionEntree(entree['text'] as String));
      }
      final sortie = contenu['outputTranscription'];
      if (sortie is Map && sortie['text'] is String) {
        _evenements.add(LiveTranscriptionSortie(sortie['text'] as String));
      }
      final tour = contenu['modelTurn'];
      if (tour is Map && tour['parts'] is List) {
        for (final p in tour['parts'] as List) {
          if (p is! Map) continue;
          final inline = p['inlineData'];
          if (inline is Map && inline['data'] is String) {
            final mime = (inline['mimeType'] ?? '').toString();
            if (mime.startsWith('audio/pcm')) {
              _evenements.add(LiveAudio(base64Decode(inline['data'] as String)));
            }
          }
        }
      }
      if (contenu['turnComplete'] == true) {
        _evenements.add(const LiveTourTermine());
      }
    }

    final appel = m['toolCall'];
    if (appel is Map && appel['functionCalls'] is List) {
      final appels = <AppelFonction>[];
      for (final f in appel['functionCalls'] as List) {
        if (f is! Map) continue;
        final args = f['args'];
        appels.add(AppelFonction(
          (f['id'] ?? '').toString(),
          (f['name'] ?? '').toString(),
          args is Map ? Map<String, dynamic>.from(args) : const {},
        ));
      }
      if (appels.isNotEmpty) _evenements.add(LiveAppelOutils(appels));
    }
  }

  void _terminer(Object? erreur) {
    if (_fermee) return;
    _fermee = true;
    // Le code de fermeture WebSocket porte la raison quand le corps ne l'a pas
    // dite : 1007/1008 sur une configuration refusée ou une clé invalide.
    final code = _canal?.closeCode;
    final raison = _canal?.closeReason;
    final detail = erreur ??
        (code != null && code != 1000 && code != 1005
            ? ErreurLive('Fermeture $code${raison == null || raison.isEmpty ? '' : ' : $raison'}')
            : null);
    if (!_pret.isCompleted) {
      _pret.completeError(detail ?? const ErreurLive('Connexion fermée.'));
    }
    _evenements.add(LiveDeconnecte(detail));
    _abonnement?.cancel();
    _evenements.close();
  }

  Future<void> fermer() async {
    if (_fermee) return;
    _fermee = true;
    await _abonnement?.cancel();
    try {
      await _canal?.sink.close(1000);
    } catch (_) {}
    if (!_evenements.isClosed) _evenements.close();
  }
}

/// Une nouvelle poignée de reprise. Le contrôleur la range dans
/// l'[EtatConnexion] ; l'écran n'a pas à la voir.
class NouveauHandleLive extends EvenementLive {
  final String handle;
  const NouveauHandleLive(this.handle);
}

String? handleDe(EvenementLive e) => e is NouveauHandleLive ? e.handle : null;

/// Doit-on essayer le modèle de repli après cet échec ?
bool basculerSurRepli(String modeleCourant, Object erreur) =>
    modeleCourant != kModeleLiveRepli && erreurDeModele(erreur);
