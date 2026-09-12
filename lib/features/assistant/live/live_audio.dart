import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart' as pcm;
import 'package:record/record.dart';

// ─── Le micro et le haut-parleur du mode vocal ────────────────────────────────

/// Niveau sonore d'un bloc PCM 16 bits, entre 0 et 1. Sert à faire respirer
/// l'orbe à l'écran, rien d'autre : pas de détection de parole ici, c'est le
/// serveur qui tranche.
double niveauPcm(Uint8List pcm) {
  if (pcm.length < 2) return 0;
  final donnees = pcm.buffer.asByteData(pcm.offsetInBytes, pcm.lengthInBytes);
  var somme = 0.0;
  final n = pcm.lengthInBytes ~/ 2;
  // Un échantillon sur quatre suffit : on mesure une ambiance, pas un signal.
  var compte = 0;
  for (var i = 0; i < n; i += 4) {
    final e = donnees.getInt16(i * 2, Endian.little) / 32768.0;
    somme += e * e;
    compte++;
  }
  if (compte == 0) return 0;
  final rms = math.sqrt(somme / compte);
  // La voix parlée normale tourne autour de 0,05–0,2 en RMS : on étire pour
  // que l'orbe bouge franchement sans saturer au moindre bruit.
  return (rms * 4).clamp(0.0, 1.0);
}

/// Le micro, en flux PCM 16 bits mono 16 kHz.
class MicroLive {
  final _enregistreur = AudioRecorder();
  StreamSubscription<Uint8List>? _abonnement;
  /// Coupé : le flux continue (l'annulation d'écho a besoin de sa référence)
  /// mais rien ne part.
  bool coupe = false;

  /// Vrai tant qu'un flux tourne.
  bool get actif => _abonnement != null;

  Future<bool> aLaPermission() => _enregistreur.hasPermission();

  Future<void> demarrer({
    required void Function(Uint8List pcm) surBloc,
    required void Function(double niveau) surNiveau,
  }) async {
    if (_abonnement != null) return;
    final flux = await _enregistreur.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      // Annulation d'écho et réduction de bruit matérielles : sans elles, le
      // micro renvoie la voix de l'assistant au serveur, qui s'interrompt
      // lui-même à chaque phrase.
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
        audioManagerMode: AudioManagerMode.modeInCommunication,
        speakerphone: true,
      ),
      iosConfig: IosRecordConfig(
        categoryOptions: [
          IosAudioCategoryOption.defaultToSpeaker,
          IosAudioCategoryOption.allowBluetooth,
        ],
      ),
    ));
    _abonnement = flux.listen((bloc) {
      surNiveau(coupe ? 0 : niveauPcm(bloc));
      if (!coupe) surBloc(bloc);
    });
  }

  Future<void> arreter() async {
    await _abonnement?.cancel();
    _abonnement = null;
    try {
      await _enregistreur.stop();
    } catch (_) {}
  }

  Future<void> liberer() async {
    await arreter();
    await _enregistreur.dispose();
  }
}

/// Le haut-parleur, PCM 16 bits mono 24 kHz.
///
/// Le lecteur natif ne sait pas vider sa file. On garde donc la nôtre côté
/// Dart et on ne lui donne que de petits blocs, à sa demande : quand
/// l'utilisateur coupe la parole, on jette notre file et il ne reste au plus
/// qu'un cinquième de seconde à s'éteindre.
class HautParleurLive {
  static const int _frequence = 24000;

  /// En dessous de ce nombre d'échantillons en réserve, le natif réclame.
  static const int _seuil = _frequence ~/ 5; // 200 ms

  /// Ce qu'on lui donne à chaque demande.
  static const int _bloc = _frequence ~/ 10; // 100 ms

  final _file = Queue<Uint8List>();
  var _reste = Uint8List(0);
  bool _pret = false;
  bool _enLecture = false;
  int _generation = 0;

  final void Function(double niveau) surNiveau;
  final void Function() surSilence;

  HautParleurLive({required this.surNiveau, required this.surSilence});

  bool get enLecture => _enLecture;

  Future<void> preparer() async {
    if (_pret) return;
    // playAndRecord : la même session audio que le micro, sinon iOS coupe
    // l'un pour laisser l'autre.
    await pcm.FlutterPcmSound.setup(
      sampleRate: _frequence,
      channelCount: 1,
      iosAudioCategory: pcm.IosAudioCategory.playAndRecord,
    );
    await pcm.FlutterPcmSound.setFeedThreshold(_seuil);
    pcm.FlutterPcmSound.setFeedCallback(_alimenter);
    _pret = true;
  }

  void jouer(Uint8List bloc) {
    if (!_pret) return;
    _file.add(bloc);
    if (!_enLecture) {
      _enLecture = true;
      pcm.FlutterPcmSound.start();
    }
  }

  /// Vide tout : interruption, ou fin de conversation.
  void couper() {
    _file.clear();
    _reste = Uint8List(0);
    _generation++;
    if (_enLecture) {
      _enLecture = false;
      surNiveau(0);
    }
  }

  void _alimenter(int restants) {
    final gen = _generation;
    const voulu = _bloc * 2; // octets
    final tampon = BytesBuilder(copy: false);
    if (_reste.isNotEmpty) {
      tampon.add(_reste);
      _reste = Uint8List(0);
    }
    while (tampon.length < voulu && _file.isNotEmpty) {
      tampon.add(_file.removeFirst());
    }
    var octets = tampon.takeBytes();
    if (octets.isEmpty) {
      if (_enLecture && restants == 0) {
        _enLecture = false;
        surNiveau(0);
        surSilence();
      }
      return;
    }
    if (octets.length > voulu) {
      _reste = Uint8List.sublistView(octets, voulu);
      octets = Uint8List.sublistView(octets, 0, voulu);
    }
    if (gen != _generation) return;
    surNiveau(niveauPcm(octets));
    pcm.FlutterPcmSound.feed(pcm.PcmArrayInt16(
        bytes: octets.buffer.asByteData(
      octets.offsetInBytes,
      octets.lengthInBytes,
    )));
  }

  Future<void> liberer() async {
    couper();
    if (!_pret) return;
    _pret = false;
    pcm.FlutterPcmSound.setFeedCallback(null);
    try {
      await pcm.FlutterPcmSound.release();
    } catch (e) {
      debugPrint('Live : libération du haut-parleur : $e');
    }
  }
}
