import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/models/models.dart';
import '../ai_actions.dart';
import '../ai_config.dart';
import '../ai_contexte.dart';
import '../ai_outils.dart';
import '../reconnaissance_vocale.dart';
import 'live_audio.dart';
import 'live_config.dart';
import 'live_session.dart';

// ─── Le chef d'orchestre du mode vocal ────────────────────────────────────────
// Relie la session Gemini Live, le micro, le haut-parleur, les outils du
// magasin et les actions. C'est lui qui décide quand reconnecter, quoi dire à
// l'écran, et ce qui finit dans l'historique.

enum PhaseLive {
  /// Rien ne tourne.
  inactif,

  /// On ouvre la session, ou on la rouvre après une coupure.
  connexion,

  /// Le micro est ouvert, l'assistant écoute.
  ecoute,

  /// Le modèle consulte le magasin ou rédige : on attend.
  reflexion,

  /// L'assistant parle.
  parole,

  /// Une action attend la confirmation à l'écran.
  confirmation,

  /// La connexion est tombée depuis assez longtemps pour qu'on le dise.
  reconnexion,

  /// Fin : clé refusée, permission micro absente, etc.
  erreur,
}

/// Une ligne de sous-titres.
@immutable
class LigneLive {
  final String role; // 'user' | 'assistant'
  final String texte;
  final bool finale;
  const LigneLive(this.role, this.texte, {this.finale = false});

  LigneLive copyWith({String? texte, bool? finale}) =>
      LigneLive(role, texte ?? this.texte, finale: finale ?? this.finale);
}

@immutable
class EtatLive {
  final PhaseLive phase;
  final List<LigneLive> lignes;
  final bool microCoupe;
  final String? message;

  /// Modèle réellement servi — le repli, parfois.
  final String? modele;

  /// Les outils consultés pendant la session, pour la trace.
  final List<String> trace;

  /// L'action proposée par le modèle, en attente de confirmation.
  final List<AppelAction> actionsEnAttente;

  const EtatLive({
    this.phase = PhaseLive.inactif,
    this.lignes = const [],
    this.microCoupe = false,
    this.message,
    this.modele,
    this.trace = const [],
    this.actionsEnAttente = const [],
  });

  bool get actif =>
      phase != PhaseLive.inactif && phase != PhaseLive.erreur;

  EtatLive copyWith({
    PhaseLive? phase,
    List<LigneLive>? lignes,
    bool? microCoupe,
    String? message,
    bool effacerMessage = false,
    String? modele,
    List<String>? trace,
    List<AppelAction>? actionsEnAttente,
  }) =>
      EtatLive(
        phase: phase ?? this.phase,
        lignes: lignes ?? this.lignes,
        microCoupe: microCoupe ?? this.microCoupe,
        message: effacerMessage ? null : (message ?? this.message),
        modele: modele ?? this.modele,
        trace: trace ?? this.trace,
        actionsEnAttente: actionsEnAttente ?? this.actionsEnAttente,
      );
}

/// Ce que le contrôleur demande à l'écran, et qu'il ne peut pas faire seul.
abstract class EcranLive {
  /// Ouvre la fiche de confirmation ; rend les actions confirmées, ou `null`.
  Future<List<AppelAction>?> confirmer(List<AppelAction> actions);

  /// Exécute une action confirmée ; rend le libellé de ce qui a été fait.
  Future<String> executer(AppelAction action);
}

class LiveController extends StateNotifier<EtatLive> {
  final Ref _ref;

  LiveSession? _session;
  StreamSubscription<EvenementLive>? _abonnement;
  final _micro = MicroLive();
  late final HautParleurLive _hautParleur;
  final _connexion = EtatConnexion();
  Timer? _reprise;
  String _modele = kModeleLivePrincipal;
  bool _arretVoulu = false;
  EcranLive? _ecran;

  /// Le tour en cours, côté modèle, s'accumule ici avant d'être « finalisé ».
  String _sortieEnCours = '';
  String _entreeEnCours = '';

  /// Niveaux sonores (0–1), hors de l'état Riverpod : ils changent cinquante
  /// fois par seconde, et redessiner toute la page à chaque fois faisait
  /// hoqueter la lecture. L'orbe les écoute directement.
  final niveauMicro = ValueNotifier<double>(0);
  final niveauVoix = ValueNotifier<double>(0);

  // ── Demi-duplex ──
  // Rien ne part vers Gemini tant que l'assistant parle ou que son tour est
  // en cours. Sans cela, le micro lui renvoie sa propre voix : son détecteur
  // d'activité croit qu'on l'interrompt, il se tait, puis reprend — et l'on
  // entend chaque mot deux fois. C'est la règle `hold_live_audio` d'ANO-GPT.

  /// Le modèle est en train de produire (audio ou texte reçu, tour pas fini).
  bool _tourModeleActif = false;

  /// On a demandé l'interruption localement : l'audio qui arrive encore est
  /// jeté jusqu'à ce que Gemini confirme (`interrupted`) ou finisse le tour.
  bool _jeterAudio = false;

  /// Blocs de micro consécutifs au-dessus du seuil de coupure.
  int _blocsForts = 0;

  /// Niveau de micro qui, tenu un instant pendant que l'assistant parle, vaut
  /// interruption. Haut à dessein : l'écho résiduel après annulation reste
  /// bien en dessous, une voix qui s'adresse au téléphone passe au-dessus.
  static const double _seuilCoupure = 0.55;
  static const int _blocsPourCouper = 6; // ≈ 150–250 ms selon le flux

  LiveController(this._ref) : super(const EtatLive()) {
    _hautParleur = HautParleurLive(
      surNiveau: (n) => niveauVoix.value = n,
      surSilence: () {
        if (!mounted) return;
        if (!_tourModeleActif) _reprendreEcoute();
      },
    );
  }

  bool get _retenirMicro =>
      _hautParleur.enLecture || _tourModeleActif || state.phase == PhaseLive.confirmation;

  void _reprendreEcoute() {
    if (!mounted) return;
    _jeterAudio = false;
    _blocsForts = 0;
    if (state.phase == PhaseLive.parole || state.phase == PhaseLive.reflexion) {
      state = state.copyWith(phase: PhaseLive.ecoute);
    }
  }

  /// Un bloc de micro. Part vers Gemini, ou sert à détecter qu'on veut couper.
  void _surBlocMicro(Uint8List pcm) {
    if (!_retenirMicro) {
      _blocsForts = 0;
      _session?.envoyerAudio(pcm);
      return;
    }
    if (_jeterAudio) {
      // On a déjà coupé : Gemini doit entendre ce qu'on dit pour s'arrêter.
      _session?.envoyerAudio(pcm);
      return;
    }
    if (niveauPcm(pcm) >= _seuilCoupure) {
      if (++_blocsForts >= _blocsPourCouper) interrompre();
    } else {
      _blocsForts = 0;
    }
  }

  /// Coupe la parole à l'assistant — parce qu'on parle fort, ou qu'on a
  /// touché l'orbe.
  void interrompre() {
    if (!_hautParleur.enLecture && !_tourModeleActif) return;
    _hautParleur.couper();
    _jeterAudio = true;
    _blocsForts = 0;
    if (_sortieEnCours.isNotEmpty) {
      _finaliser('assistant', suffixe: ' …');
      _sortieEnCours = '';
    }
    if (mounted) state = state.copyWith(phase: PhaseLive.ecoute);
    if (_ref.read(configLiveProvider).retourHaptique) {
      HapticFeedback.selectionClick();
    }
  }

  set ecran(EcranLive? e) => _ecran = e;

  // ── Démarrage / arrêt ───────────────────────────────────────────────────

  Future<void> demarrer() async {
    if (state.actif) return;
    _arretVoulu = false;

    final cfg = _ref.read(configIAProvider);
    final cles = cfg.cles[FournisseurIA.gemini] ?? '';
    final cle = cles
        .split(RegExp(r'[\s,;]+'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .firstOrNull;
    if (cle == null) {
      state = state.copyWith(
        phase: PhaseLive.erreur,
        message:
            'Le mode vocal a besoin d\'une clé Gemini. Ouvrez Paramètres → Assistant IA.',
      );
      return;
    }

    if (!await _micro.aLaPermission()) {
      state = state.copyWith(
        phase: PhaseLive.erreur,
        message: 'Sans accès au micro, l\'assistant ne peut pas vous entendre.',
      );
      return;
    }

    state = const EtatLive(phase: PhaseLive.connexion);
    _modele = kModeleLivePrincipal;

    try {
      await _hautParleur.preparer();
    } catch (e) {
      state = state.copyWith(
          phase: PhaseLive.erreur, message: 'Haut-parleur indisponible : $e');
      return;
    }

    await _ouvrir(cle);
  }

  Future<void> _ouvrir(String cle) async {
    if (_arretVoulu) return;
    final cfgLive = _ref.read(configLiveProvider);
    final donnees = _ref.read(donneesMagasinProvider);
    final compte = _ref.read(authStateProvider).value?.user;

    final session = LiveSession(
      cle: cle,
      modele: _modele,
      voix: cfgLive.voix,
      instructionSysteme: _instruction(donnees, compte),
      outils: _declarations(donnees, compte),
      handleReprise: _connexion.handle,
    );

    try {
      _session = session;
      _abonnement = session.evenements.listen(_surEvenement);
      await session.ouvrir();
    } catch (e) {
      _abonnement?.cancel();
      _session = null;
      if (_arretVoulu) return;

      if (basculerSurRepli(_modele, e)) {
        debugPrint('Live : $_modele refusé, repli sur $kModeleLiveRepli ($e)');
        _modele = kModeleLiveRepli;
        return _ouvrir(cle);
      }
      if (erreurDeCle(e)) {
        await _toutArreter();
        state = state.copyWith(
            phase: PhaseLive.erreur,
            message: 'La clé Gemini est refusée. Vérifiez-la dans les paramètres.');
        return;
      }
      // Une poignée périmée fait refuser la configuration : on repart d'une
      // session neuve plutôt que d'insister.
      if (_connexion.handle != null) {
        _connexion.oublierSession();
        return _ouvrir(cle);
      }
      _planifierReprise(cle, e);
      return;
    }

    _connexion.surConnexion();
    state = state.copyWith(
      phase: PhaseLive.ecoute,
      modele: _modele,
      effacerMessage: true,
    );

    try {
      await _micro.demarrer(
        surBloc: _surBlocMicro,
        surNiveau: (n) => niveauMicro.value = n,
      );
    } catch (e) {
      await _toutArreter();
      state = state.copyWith(
          phase: PhaseLive.erreur, message: 'Micro indisponible : $e');
    }
  }

  void _planifierReprise(String cle, Object? erreur) {
    _connexion.surDeconnexion();
    if (_connexion.dureeCoupure >= EtatConnexion.conversationPerdue) {
      _toutArreter();
      state = state.copyWith(
        phase: PhaseLive.erreur,
        message: 'La connexion est perdue. ${erreur == null ? '' : '($erreur)'}',
      );
      return;
    }
    if (_connexion.coupureVisible) {
      state = state.copyWith(
        phase: PhaseLive.reconnexion,
        message: 'Connexion perdue, on réessaie…',
      );
    } else {
      state = state.copyWith(phase: PhaseLive.connexion);
    }
    _reprise?.cancel();
    _reprise = Timer(_connexion.prochainDelai, () => _ouvrir(cle));
  }

  /// Fin voulue par l'utilisateur. L'écran a lu les sous-titres avant, s'il
  /// veut les verser dans l'historique : ici on ne garde rien.
  Future<void> arreter() async {
    _arretVoulu = true;
    await _toutArreter();
    state = const EtatLive();
  }

  Future<void> _toutArreter() async {
    _tourModeleActif = false;
    _jeterAudio = false;
    _blocsForts = 0;
    niveauMicro.value = 0;
    niveauVoix.value = 0;
    _reprise?.cancel();
    _reprise = null;
    await _abonnement?.cancel();
    _abonnement = null;
    await _session?.fermer();
    _session = null;
    await _micro.arreter();
    _hautParleur.couper();
  }

  void couperMicro(bool coupe) {
    _micro.coupe = coupe;
    niveauMicro.value = 0;
    state = state.copyWith(microCoupe: coupe);
  }

  /// Un message tapé pendant la conversation.
  void envoyerTexte(String texte) {
    final t = texte.trim();
    if (t.isEmpty || _session == null) return;
    _hautParleur.couper();
    _jeterAudio = false;
    _tourModeleActif = true;
    _ajouterLigne(LigneLive('user', t, finale: true));
    state = state.copyWith(phase: PhaseLive.reflexion);
    _session!.envoyerTexte(t);
  }

  // ── Évènements du serveur ───────────────────────────────────────────────

  Future<void> _surEvenement(EvenementLive e) async {
    if (!mounted) return;
    final h = handleDe(e);
    if (h != null) {
      _connexion.surHandle(h);
      return;
    }

    switch (e) {
      case LivePret():
        break;

      case NouveauHandleLive():
        // Déjà rangé ci-dessus.
        break;

      case LiveAudio(:final pcm):
        _tourModeleActif = true;
        if (_jeterAudio) return;
        if (state.phase != PhaseLive.parole) {
          if (_ref.read(configLiveProvider).retourHaptique) {
            HapticFeedback.lightImpact();
          }
          state = state.copyWith(phase: PhaseLive.parole);
        }
        _hautParleur.jouer(pcm);

      case LiveTranscriptionEntree(:final texte):
        // Correction uniquement des confusions métier sûres dans le sous-titre.
        // L'audio original reste la source pour Gemini ; aucune valeur sensible
        // n'est devinée et toute écriture exige toujours la fiche tactile.
        _entreeEnCours += normaliserTranscriptionMetier(texte);
        _mettreAJourLigne('user', _entreeEnCours);

      case LiveTranscriptionSortie(:final texte):
        _tourModeleActif = true;
        if (_jeterAudio) return;
        // Un nouveau tour du modèle clôt ce que l'utilisateur disait.
        if (_entreeEnCours.isNotEmpty) {
          _finaliser('user');
          _entreeEnCours = '';
        }
        _sortieEnCours += texte;
        _mettreAJourLigne('assistant', _sortieEnCours);

      case LiveInterrompu():
        _hautParleur.couper();
        _tourModeleActif = false;
        if (_sortieEnCours.isNotEmpty) {
          _finaliser('assistant', suffixe: ' …');
          _sortieEnCours = '';
        }
        _reprendreEcoute();

      case LiveTourTermine():
        _tourModeleActif = false;
        if (_sortieEnCours.isNotEmpty) {
          _finaliser('assistant');
          _sortieEnCours = '';
        }
        if (_entreeEnCours.isNotEmpty) {
          _finaliser('user');
          _entreeEnCours = '';
        }
        // Le haut-parleur finit sa file ; c'est lui qui rouvrira le micro.
        if (!_hautParleur.enLecture) _reprendreEcoute();

      case LiveAppelOutils(:final appels):
        _tourModeleActif = true;
        await _executerOutils(appels);

      case LiveFermetureAnnoncee():
        _connexion.fermeturePrevue = true;

      case LiveDeconnecte(:final erreur):
        // Déjà traité par l'échec d'ouverture, ou fin voulue.
        if (_arretVoulu || _session == null) return;
        await _micro.arreter();
        _hautParleur.couper();
        _abonnement?.cancel();
        _abonnement = null;
        _session = null;
        final cfg = _ref.read(configIAProvider);
        final cle = cfg.cles[FournisseurIA.gemini]
                ?.split(RegExp(r'[\s,;]+'))
                .firstWhere((c) => c.trim().isNotEmpty, orElse: () => '') ??
            '';
        if (erreur != null && erreurDeCle(erreur)) {
          state = state.copyWith(
              phase: PhaseLive.erreur,
              message: 'La clé Gemini est refusée. Vérifiez-la dans les paramètres.');
          return;
        }
        _planifierReprise(cle, erreur);
    }
  }

  // ── Sous-titres ─────────────────────────────────────────────────────────

  void _ajouterLigne(LigneLive l) {
    state = state.copyWith(lignes: [...state.lignes, l]);
  }

  void _mettreAJourLigne(String role, String texte) {
    final lignes = [...state.lignes];
    if (lignes.isNotEmpty &&
        lignes.last.role == role &&
        !lignes.last.finale) {
      lignes[lignes.length - 1] = lignes.last.copyWith(texte: texte);
    } else {
      lignes.add(LigneLive(role, texte));
    }
    state = state.copyWith(lignes: lignes);
  }

  void _finaliser(String role, {String suffixe = ''}) {
    final lignes = [...state.lignes];
    if (lignes.isNotEmpty && lignes.last.role == role && !lignes.last.finale) {
      final l = lignes.last;
      lignes[lignes.length - 1] =
          l.copyWith(texte: l.texte.trim() + suffixe, finale: true);
      state = state.copyWith(lignes: lignes);
    }
  }

  // ── Outils et actions ───────────────────────────────────────────────────

  Future<void> _executerOutils(List<AppelFonction> appels) async {
    final session = _session;
    if (session == null) return;
    state = state.copyWith(phase: PhaseLive.reflexion);

    final donnees = _ref.read(donneesMagasinProvider);
    final compte = _ref.read(authStateProvider).value?.user;
    final resultats = <AppelFonction, String>{};
    final trace = [...state.trace];

    // Les outils de lecture d'abord, tous ensemble : ils sont locaux et
    // immédiats. Les actions ensuite, car elles ouvrent une fiche et attendent
    // un humain.
    final actions = <AppelFonction>[];
    for (final a in appels) {
      if (a.nom == 'proposer_action') {
        actions.add(a);
        continue;
      }
      final r = executerOutil(AppelOutil(a.nom, a.args), donnees);
      resultats[a] = r;
      if (!trace.contains(a.nom)) trace.add(a.nom);
    }
    state = state.copyWith(trace: trace);

    for (final a in actions) {
      resultats[a] = await _proposerAction(a, compte);
    }

    session.repondreOutils(resultats);
    if (mounted && state.phase == PhaseLive.confirmation) {
      state = state.copyWith(phase: PhaseLive.reflexion);
    }
  }

  /// L'action passe par la même fiche de confirmation qu'en mode texte :
  /// rien ne s'écrit sur un « oui » entendu au micro.
  Future<String> _proposerAction(AppelFonction a, Utilisateur? compte) async {
    final type = (a.args['type'] ?? '').toString();
    final brut = a.args['params'];
    final params = brut is Map
        ? Map<String, dynamic>.from(brut)
        : (Map<String, dynamic>.from(a.args)..remove('type'));
    final libelle = (a.args['libelle'] ?? type).toString();

    final v = verifierAction(type, params, compte);
    if (!v.ok) return 'Refusé : ${v.motif}';

    final ecran = _ecran;
    if (ecran == null) {
      return 'Impossible d\'afficher la fiche de confirmation pour le moment.';
    }

    final appel = AppelAction(canoniser(type), params, libelle);
    state = state.copyWith(
        phase: PhaseLive.confirmation, actionsEnAttente: [appel]);
    // La voix se tait pendant la fiche : le commerçant lit, il n'écoute pas.
    _micro.coupe = true;
    try {
      final confirmees = await ecran.confirmer([appel]);
      if (confirmees == null || confirmees.isEmpty) {
        return 'L\'utilisateur a annulé. Ne réessaie pas sans qu\'il le demande.';
      }
      final faits = <String>[];
      for (final c in confirmees) {
        try {
          faits.add(await ecran.executer(c));
        } catch (e) {
          return 'Échec : $e';
        }
      }
      return 'Fait : ${faits.join(' ; ')}. Dis-le en une phrase.';
    } finally {
      _micro.coupe = state.microCoupe;
      if (mounted) state = state.copyWith(actionsEnAttente: const []);
    }
  }

  List<Map<String, dynamic>> _declarations(
      DonneesMagasin d, Utilisateur? compte) {
    final decl = <Map<String, dynamic>>[
      for (final o in kOutils)
        if (d.voitPrixAchat || !o.confidentiel)
          declarationFonction(
            nom: o.nom,
            description: o.description,
            parametres: o.parametres,
          ),
    ];

    final permises = actionsEcriture(compte);
    if (permises.isNotEmpty) {
      final catalogue = permises.map((a) {
        final champs = a.champs
            .map((c) => '${c.nom}${c.requis ? '*' : ''} (${c.libelle})')
            .join(', ');
        return '• ${a.type} : ${a.titre} — champs : $champs';
      }).join('\n');
      decl.add({
        'name': 'proposer_action',
        'description':
            'Propose une écriture dans le magasin (vente, entrée de stock, dépense, '
            'client…). Une fiche s\'ouvre à l\'écran et l\'utilisateur confirme du '
            'doigt : rien n\'est écrit avant. Dès qu\'un article est nommé, appelle '
            'd\'abord resoudre_article pour trouver son identifiant exact.\n'
            'Actions disponibles (les champs marqués * sont obligatoires) :\n$catalogue',
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            'type': {
              'type': 'STRING',
              'description': 'Le type d\'action, parmi la liste ci-dessus.'
            },
            'libelle': {
              'type': 'STRING',
              'description': 'Ce qui va être fait, en une courte phrase.'
            },
            'params': {
              'type': 'OBJECT',
              'description': 'Les champs de l\'action, nom → valeur.',
              'properties': {
                for (final a in permises)
                  for (final c in a.champs)
                    c.nom: {'type': 'STRING', 'description': c.libelle},
              },
            },
          },
          'required': ['type', 'params'],
        },
      });
    }
    return decl;
  }

  String _instruction(DonneesMagasin d, Utilisateur? compte) {
    final contexte = _ref.read(contexteIAProvider);
    return '''$contexte

═══════════ MODE VOCAL ═══════════
Tu es en conversation ORALE avec le commerçant, au comptoir, en français.
- Réponds court : une à trois phrases. Pas de liste, pas de tableau, pas de markdown, pas de symbole. Les montants se disent en toutes lettres, en francs guinéens (« deux millions trois cent mille francs »).
- Les outils ci-dessus s'appellent par FONCTION (function calling), jamais en écrivant une balise <outil> ni un bloc ```action```. Ces formats textuels ne s'appliquent pas en vocal.
- Pour écrire quelque chose dans le magasin, appelle proposer_action ; l'utilisateur confirme à l'écran. Annonce ce que tu proposes en une phrase, puis attends le résultat.
- Avant toute proposition qui contient une quantité, un prix, une dimension ou un article, redis ces éléments à voix haute et demande à l'utilisateur de les vérifier sur la fiche. Un « oui » entendu au micro n'autorise jamais l'écriture.
- Quand un outil tourne, dis simplement « je regarde » et reprends après.
- Si tu n'as pas compris, demande de répéter en une phrase, sans t'excuser longuement.
- Reste sur le magasin. Bruit de fond ou phrase qui ne t'est pas adressée : reste silencieux.''';
  }

  @override
  void dispose() {
    _arretVoulu = true;
    _toutArreter();
    _micro.liberer();
    _hautParleur.liberer();
    niveauMicro.dispose();
    niveauVoix.dispose();
    super.dispose();
  }
}

final liveControllerProvider =
    StateNotifierProvider<LiveController, EtatLive>((ref) {
  return LiveController(ref);
});
