import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/auth/auth_state.dart';
import '../../dashboard/dashboard_page.dart' show tousArticlesProvider;
import '../../ventes/ventes_page.dart' show tousClientsProvider;
import '../action_executeur.dart';
import '../action_sheet.dart';
import '../ai_actions.dart';
import '../assistant_page.dart' show ChatMessage, chatSessionsProvider;
import 'live_config.dart';
import 'live_controller.dart';

// ─── L'écran du mode vocal ────────────────────────────────────────────────────
// Plein écran, sombre, une orbe au centre qui respire avec la voix — la
// sienne quand on parle, celle de l'assistant quand il répond. Les couleurs
// sont celles de l'application : l'orange de la marque et sa teinte tertiaire.

class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage>
    with SingleTickerProviderStateMixin
    implements EcranLive {
  late final AnimationController _horloge;
  final _clavier = TextEditingController();
  final _defilement = ScrollController();
  bool _clavierOuvert = false;
  bool _sousTitres = true;

  @override
  void initState() {
    super.initState();
    _horloge = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _sousTitres = ref.read(configLiveProvider).sousTitres;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = ref.read(liveControllerProvider.notifier);
      ctrl.ecran = this;
      ctrl.demarrer();
    });
  }

  @override
  void dispose() {
    final ctrl = ref.read(liveControllerProvider.notifier);
    ctrl.ecran = null;
    _horloge.dispose();
    _clavier.dispose();
    _defilement.dispose();
    super.dispose();
  }

  // ── EcranLive ───────────────────────────────────────────────────────────

  @override
  Future<List<AppelAction>?> confirmer(List<AppelAction> actions) {
    final compte = ref.read(authStateProvider).value?.user;
    return ouvrirFicheActions(
      context,
      actions: actions,
      contexte: ContexteResume(
        articles: ref.read(tousArticlesProvider).valueOrNull ?? const [],
        clients: ref.read(tousClientsProvider).valueOrNull ?? const [],
      ),
      manquantsDe: (a) {
        final v = verifierAction(a.type, a.params, compte);
        return v.ok ? v.manquants : const [];
      },
    );
  }

  @override
  Future<String> executer(AppelAction action) async {
    final r = await ref.read(executeurActionsProvider).executer(action);
    return r.libelle;
  }

  // ── Fin ─────────────────────────────────────────────────────────────────

  Future<void> _terminer() async {
    final etat = ref.read(liveControllerProvider);
    final ctrl = ref.read(liveControllerProvider.notifier);

    // Ce qui s'est dit rejoint la discussion écrite, pour qu'on puisse le
    // relire — et pour que le mode texte sache de quoi on vient de parler.
    if (ref.read(configLiveProvider).journaliser) {
      final notifier = ref.read(chatSessionsProvider.notifier);
      final lignes = etat.lignes.where((l) => l.texte.trim().isNotEmpty);
      for (final l in lignes) {
        await notifier.addMessageToActiveSession(ChatMessage(
          role: l.role,
          content: l.role == 'user' ? '🎙️ ${l.texte}' : l.texte,
          timestamp: DateTime.now(),
        ));
      }
    }
    await ctrl.arreter();
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/assistant');
      }
    }
  }

  void _envoyerClavier() {
    final t = _clavier.text.trim();
    if (t.isEmpty) return;
    ref.read(liveControllerProvider.notifier).envoyerTexte(t);
    _clavier.clear();
    setState(() => _clavierOuvert = false);
    FocusScope.of(context).unfocus();
  }

  void _defilerEnBas() {
    if (!_defilement.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_defilement.hasClients) return;
      _defilement.animateTo(
        _defilement.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final etat = ref.watch(liveControllerProvider);
    ref.listen(liveControllerProvider.select((e) => e.lignes.length),
        (_, __) => _defilerEnBas());
    ref.listen(
        liveControllerProvider
            .select((e) => e.lignes.isEmpty ? '' : e.lignes.last.texte),
        (_, __) => _defilerEnBas());

    // Fond : un noir teinté de la marque, plus profond en bas.
    final fondHaut = Color.lerp(scheme.primary, const Color(0xFF0B0A0F), 0.90)!;
    const fondBas = Color(0xFF07060A);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _terminer();
      },
      child: Scaffold(
        backgroundColor: fondBas,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [fondHaut, fondBas],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _EnTete(
                  etat: etat,
                  onFermer: _terminer,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        flex: _sousTitres && etat.lignes.isNotEmpty ? 5 : 8,
                        child: Center(
                          child: GestureDetector(
                            // Toucher l'orbe pendant qu'il parle le coupe :
                            // plus sûr que d'élever la voix au comptoir.
                            onTap: () => ref
                                .read(liveControllerProvider.notifier)
                                .interrompre(),
                            child: _Orbe(
                              horloge: _horloge,
                              phase: etat.phase,
                              niveauMicro: ref
                                  .read(liveControllerProvider.notifier)
                                  .niveauMicro,
                              niveauVoix: ref
                                  .read(liveControllerProvider.notifier)
                                  .niveauVoix,
                              primaire: scheme.primary,
                              secondaire: scheme.tertiary,
                            ),
                          ),
                        ),
                      ),
                      _Statut(etat: etat),
                      if (_sousTitres && etat.lignes.isNotEmpty)
                        Expanded(
                          flex: 4,
                          child: _SousTitres(
                            lignes: etat.lignes,
                            controleur: _defilement,
                            accent: scheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_clavierOuvert)
                  _BarreClavier(
                    controleur: _clavier,
                    onEnvoyer: _envoyerClavier,
                    onFermer: () => setState(() => _clavierOuvert = false),
                    accent: scheme.primary,
                  )
                else
                  _BarreActions(
                    etat: etat,
                    sousTitres: _sousTitres,
                    onMicro: () => ref
                        .read(liveControllerProvider.notifier)
                        .couperMicro(!etat.microCoupe),
                    onSousTitres: () {
                      setState(() => _sousTitres = !_sousTitres);
                      ref
                          .read(configLiveProvider.notifier)
                          .activerSousTitres(_sousTitres);
                    },
                    onClavier: () => setState(() => _clavierOuvert = true),
                    onFermer: _terminer,
                    onReessayer: () =>
                        ref.read(liveControllerProvider.notifier).demarrer(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── En-tête ──────────────────────────────────────────────────────────────────

class _EnTete extends StatelessWidget {
  final EtatLive etat;
  final VoidCallback onFermer;
  const _EnTete({required this.etat, required this.onFermer});

  @override
  Widget build(BuildContext context) {
    final modele = etat.modele;
    final libelle = modele == null
        ? 'Gemini Live'
        : modele.contains('2.5')
            ? 'Gemini Live · repli'
            : 'Gemini Live';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onFermer,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            color: Colors.white70,
            iconSize: 28,
            tooltip: 'Quitter le mode vocal',
          ),
          const Spacer(),
          AnimatedOpacity(
            duration: Duree.moyenne,
            opacity: etat.actif ? 1 : 0.4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(Rayon.pilule),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PointVivant(actif: etat.phase == PhaseLive.ecoute ||
                      etat.phase == PhaseLive.parole),
                  const SizedBox(width: 8),
                  Text(
                    libelle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PointVivant extends StatefulWidget {
  final bool actif;
  const _PointVivant({required this.actif});
  @override
  State<_PointVivant> createState() => _PointVivantState();
}

class _PointVivantState extends State<_PointVivant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = widget.actif ? const Color(0xFF34D399) : Colors.white38;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: couleur,
          boxShadow: widget.actif
              ? [
                  BoxShadow(
                    color: couleur.withValues(alpha: 0.35 + 0.35 * _c.value),
                    blurRadius: 6 + 6 * _c.value,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
      ),
    );
  }
}

// ─── L'orbe ───────────────────────────────────────────────────────────────────

class _Orbe extends StatefulWidget {
  final AnimationController horloge;
  final PhaseLive phase;
  final ValueListenable<double> niveauMicro;
  final ValueListenable<double> niveauVoix;
  final Color primaire;
  final Color secondaire;
  const _Orbe({
    required this.horloge,
    required this.phase,
    required this.niveauMicro,
    required this.niveauVoix,
    required this.primaire,
    required this.secondaire,
  });

  @override
  State<_Orbe> createState() => _OrbeState();
}

class _OrbeState extends State<_Orbe> {
  // Les niveaux bruts sautent d'un bloc à l'autre ; on les lisse à chaque
  // image pour que l'orbe gonfle et dégonfle comme une respiration, pas
  // comme un vu-mètre. Le lissage se fait ici, dans le rythme de l'horloge :
  // aucun setState, aucune reconstruction de la page.
  double _niveau = 0;

  @override
  Widget build(BuildContext context) {
    final taille = math.min(MediaQuery.sizeOf(context).width * 0.62, 260.0);

    return AnimatedBuilder(
      animation: Listenable.merge(
          [widget.horloge, widget.niveauMicro, widget.niveauVoix]),
      builder: (context, _) {
        final cible = switch (widget.phase) {
          PhaseLive.parole => widget.niveauVoix.value,
          PhaseLive.ecoute => widget.niveauMicro.value * 0.7,
          _ => 0.0,
        };
        // Monte vite, redescend lentement.
        _niveau = cible > _niveau
            ? _niveau + (cible - _niveau) * 0.5
            : _niveau + (cible - _niveau) * 0.12;
        return CustomPaint(
          size: Size.square(taille * 1.6),
          painter: _PeintreOrbe(
            temps: widget.horloge.value,
            niveau: _niveau,
            phase: widget.phase,
            primaire: widget.primaire,
            secondaire: widget.secondaire,
            rayonBase: taille / 2,
          ),
        );
      },
    );
  }
}

class _PeintreOrbe extends CustomPainter {
  final double temps; // 0..1, boucle
  final double niveau; // 0..1
  final PhaseLive phase;
  final Color primaire;
  final Color secondaire;
  final double rayonBase;

  _PeintreOrbe({
    required this.temps,
    required this.niveau,
    required this.phase,
    required this.primaire,
    required this.secondaire,
    required this.rayonBase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final t = temps * 2 * math.pi;

    final enConnexion = phase == PhaseLive.connexion ||
        phase == PhaseLive.reconnexion ||
        phase == PhaseLive.reflexion;
    final enErreur = phase == PhaseLive.erreur;
    final coupe = phase == PhaseLive.inactif;

    // Respiration de fond, toujours là ; la voix s'ajoute par-dessus.
    final respiration = 0.03 * math.sin(t * 2);
    final gonfle = 1 + respiration + niveau * 0.32;
    final rayon = rayonBase * gonfle;

    final teinte = enErreur
        ? const Color(0xFFEF4444)
        : coupe
            ? Colors.white38
            : primaire;
    final teinte2 = enErreur
        ? const Color(0xFFF87171)
        : coupe
            ? Colors.white24
            : secondaire;

    // Halo diffus.
    final halo = Paint()
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 40)
      ..color = teinte.withValues(alpha: 0.18 + niveau * 0.25);
    canvas.drawCircle(centre, rayon * 1.15, halo);

    // Trois lobes qui tournent à des vitesses différentes : c'est ce qui donne
    // l'impression d'une matière vivante plutôt que d'un disque qui grossit.
    for (var i = 0; i < 3; i++) {
      final dec = i * 2 * math.pi / 3;
      final vitesse = enConnexion ? 3.0 : 1.0;
      final chemin = _lobe(
        centre,
        rayon * (0.92 + 0.04 * i),
        t * vitesse + dec,
        amplitude: 0.06 + niveau * 0.10 + (enConnexion ? 0.05 : 0),
        harmoniques: 3 + i,
      );
      final couleur = Color.lerp(teinte, teinte2, i / 2)!;
      final peinture = Paint()
        ..shader = ui.Gradient.radial(
          centre.translate(-rayon * 0.25, -rayon * 0.3),
          rayon * 1.3,
          [
            couleur.withValues(alpha: 0.95),
            couleur.withValues(alpha: 0.55),
            couleur.withValues(alpha: 0.10),
          ],
          const [0.0, 0.55, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
      canvas.drawPath(chemin, peinture);
    }

    // Cœur plus clair.
    final coeur = Paint()
      ..shader = ui.Gradient.radial(
        centre.translate(-rayon * 0.2, -rayon * 0.25),
        rayon * 0.9,
        [
          Colors.white.withValues(alpha: 0.55 + niveau * 0.3),
          Colors.white.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(centre, rayon * 0.75, coeur);

    // Anneau de réflexion : un trait fin qui tourne pendant qu'on attend.
    if (enConnexion) {
      final anneau = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.sweep(
          centre,
          [Colors.transparent, Colors.white.withValues(alpha: 0.9)],
          const [0.55, 1.0],
          TileMode.clamp,
          t * 4,
          t * 4 + 2 * math.pi,
        );
      canvas.drawCircle(centre, rayon * 1.32, anneau);
    }
  }

  Path _lobe(
    Offset c,
    double r,
    double phase, {
    required double amplitude,
    required int harmoniques,
  }) {
    const n = 90;
    final p = Path();
    for (var i = 0; i <= n; i++) {
      final a = i / n * 2 * math.pi;
      final d = 1 +
          amplitude * math.sin(harmoniques * a + phase) +
          amplitude * 0.5 * math.sin((harmoniques + 2) * a - phase * 1.7);
      final x = c.dx + r * d * math.cos(a);
      final y = c.dy + r * d * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_PeintreOrbe o) =>
      o.temps != temps ||
      o.niveau != niveau ||
      o.phase != phase ||
      o.rayonBase != rayonBase;
}

// ─── Statut ───────────────────────────────────────────────────────────────────

class _Statut extends StatelessWidget {
  final EtatLive etat;
  const _Statut({required this.etat});

  @override
  Widget build(BuildContext context) {
    final (titre, sous) = switch (etat.phase) {
      PhaseLive.inactif => ('Terminé', null),
      PhaseLive.connexion => ('Connexion…', null),
      PhaseLive.ecoute => etat.microCoupe
          ? ('Micro coupé', 'Touchez le micro pour reprendre')
          : ('Je vous écoute', 'Parlez naturellement'),
      PhaseLive.reflexion => ('Je regarde…', 'Consultation du magasin'),
      PhaseLive.parole => ('', 'Touchez l\'orbe pour me couper'),
      PhaseLive.confirmation => ('À confirmer', 'Lisez la fiche à l\'écran'),
      PhaseLive.reconnexion => ('Reconnexion…', etat.message),
      PhaseLive.erreur => ('Impossible de continuer', etat.message),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      child: AnimatedSwitcher(
        duration: Duree.moyenne,
        child: Column(
          key: ValueKey('${etat.phase}-${etat.microCoupe}-${etat.message}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titre.isNotEmpty)
              Text(
                titre,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            if (sous != null && sous.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                sous,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Sous-titres ──────────────────────────────────────────────────────────────

class _SousTitres extends StatelessWidget {
  final List<LigneLive> lignes;
  final ScrollController controleur;
  final Color accent;
  const _SousTitres({
    required this.lignes,
    required this.controleur,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white, Colors.white],
        stops: [0, 0.12, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: controleur,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        itemCount: lignes.length,
        itemBuilder: (context, i) {
          final l = lignes[i];
          final moi = l.role == 'user';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment:
                  moi ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: AnimatedContainer(
                    duration: Duree.rapide,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: moi
                          ? accent.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(moi ? 18 : 6),
                        bottomRight: Radius.circular(moi ? 6 : 18),
                      ),
                    ),
                    child: Text(
                      l.texte,
                      style: TextStyle(
                        color: Colors.white.withValues(
                            alpha: l.finale ? 0.92 : 0.7),
                        fontSize: 15,
                        height: 1.35,
                        fontStyle:
                            l.finale ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Barre d'actions ──────────────────────────────────────────────────────────

class _BarreActions extends StatelessWidget {
  final EtatLive etat;
  final bool sousTitres;
  final VoidCallback onMicro;
  final VoidCallback onSousTitres;
  final VoidCallback onClavier;
  final VoidCallback onFermer;
  final VoidCallback onReessayer;

  const _BarreActions({
    required this.etat,
    required this.sousTitres,
    required this.onMicro,
    required this.onSousTitres,
    required this.onClavier,
    required this.onFermer,
    required this.onReessayer,
  });

  @override
  Widget build(BuildContext context) {
    final enErreur = etat.phase == PhaseLive.erreur;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Rond(
            icone: sousTitres
                ? Icons.closed_caption_rounded
                : Icons.closed_caption_disabled_rounded,
            libelle: sousTitres ? 'Sous-titres' : 'Sans texte',
            actif: sousTitres,
            accent: sousTitres,
            onTap: onSousTitres,
          ),
          _Rond(
            icone: etat.microCoupe ? Icons.mic_off_rounded : Icons.mic_rounded,
            libelle: etat.microCoupe ? 'Coupé' : 'Micro',
            actif: !etat.microCoupe,
            alerte: etat.microCoupe,
            onTap: etat.actif ? onMicro : null,
          ),
          _Rond(
            icone: enErreur ? Icons.refresh_rounded : Icons.close_rounded,
            libelle: enErreur ? 'Réessayer' : 'Terminer',
            principal: true,
            danger: !enErreur,
            onTap: enErreur ? onReessayer : onFermer,
          ),
          _Rond(
            icone: Icons.keyboard_rounded,
            libelle: 'Clavier',
            onTap: etat.actif ? onClavier : null,
          ),
        ],
      ),
    );
  }
}

class _Rond extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final bool actif;
  final bool alerte;
  final bool principal;
  final bool danger;

  /// Réglage « allumé » : fond de la couleur de la marque, pour qu'on voie
  /// qu'il l'est.
  final bool accent;
  final VoidCallback? onTap;

  const _Rond({
    required this.icone,
    required this.libelle,
    this.actif = false,
    this.alerte = false,
    this.principal = false,
    this.danger = false,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final taille = principal ? 72.0 : 56.0;
    final Color fond;
    final Color encre;
    final marque = Theme.of(context).colorScheme.primary;
    if (principal) {
      fond = danger ? const Color(0xFFEF4444) : Colors.white;
      encre = danger ? Colors.white : Colors.black87;
    } else if (accent) {
      fond = marque;
      encre = Colors.white;
    } else if (alerte) {
      fond = const Color(0xFFEF4444).withValues(alpha: 0.22);
      encre = const Color(0xFFF87171);
    } else {
      fond = Colors.white.withValues(alpha: actif ? 0.16 : 0.08);
      encre = Colors.white.withValues(alpha: onTap == null ? 0.35 : 0.92);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: fond,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: taille,
              height: taille,
              child: Icon(icone, color: encre, size: principal ? 30 : 24),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          libelle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: accent ? 0.95 : 0.55),
            fontSize: 11.5,
            fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _BarreClavier extends StatelessWidget {
  final TextEditingController controleur;
  final VoidCallback onEnvoyer;
  final VoidCallback onFermer;
  final Color accent;

  const _BarreClavier({
    required this.controleur,
    required this.onEnvoyer,
    required this.onFermer,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: onFermer,
            icon: const Icon(Icons.mic_rounded),
            color: Colors.white70,
            tooltip: 'Revenir à la voix',
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Rayon.lg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: controleur,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onEnvoyer(),
                decoration: InputDecoration(
                  hintText: 'Écrire à l\'assistant…',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: accent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onEnvoyer,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
