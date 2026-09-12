import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/auth/auth_state.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_state.dart';
import 'appareils_section.dart';
import 'assistant_section.dart';
import 'entreprise_form.dart';
import 'sauvegarde_section.dart';
import 'securite_section.dart';
import 'utilisateurs_section.dart';

class ParametresPage extends ConsumerStatefulWidget {
  const ParametresPage({super.key});

  @override
  ConsumerState<ParametresPage> createState() => _ParametresPageState();
}

class _ParametresPageState extends ConsumerState<ParametresPage> {
  void _retourSecurise(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accueil');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authState = ref.watch(authStateProvider);
    final user = authState.value?.user;
    final themeMode = ref.watch(themeModeProvider);
    final syncState = ref.watch(syncStateProvider);

    final initiales = (user?.nom != null && user!.nom.trim().isNotEmpty)
        ? user.nom.trim().substring(0, 1).toUpperCase()
        : '?';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Paramètres'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              Espace.page, Espace.sm, Espace.page, Espace.basDeListe),
          children: [
            // ── Le compte, en tête ──
            _EnTeteCompte(
              initiales: initiales,
              nom: user?.nom ?? 'Utilisateur',
              email: user?.email ?? 'Connecté',
              synchro: syncState.pendingCount == 0,
              enAttente: syncState.pendingCount,
            ),
            const SizedBox(height: Espace.xl),

            // Chaque section n'apparaît qu'à qui a le droit d'y toucher. Le
            // serveur refuse de toute façon les écritures ; ce masquage évite
            // d'ouvrir un formulaire dont l'enregistrement échouera.
            if ((user?.aLeDroit('entreprise') ?? false) ||
                (user?.aLeDroit('utilisateurs') ?? false) ||
                (user?.aLeDroit('appareils') ?? false)) ...[
              const _TitreGroupe('Magasin'),
              if (user?.aLeDroit('entreprise') ?? false)
                const _Volet(
                  titre: 'Fiche entreprise',
                  sousTitre: 'Logo, NIF, RCCM, coordonnées, banque',
                  icone: Icons.storefront_rounded,
                  teinte: Color(0xFFFF5E1A),
                  child: EntrepriseForm(isEmbedded: true),
                ),
              if (user?.aLeDroit('utilisateurs') ?? false)
                const _Volet(
                  titre: 'Utilisateurs & droits',
                  sousTitre: 'Comptes du magasin et ce qu\'ils peuvent faire',
                  icone: Icons.group_rounded,
                  teinte: Color(0xFF6366F1),
                  child: UtilisateursSection(isEmbedded: true),
                ),
              if (user?.aLeDroit('appareils') ?? false)
                const _Volet(
                  titre: 'Appareils de confiance',
                  sousTitre: 'Téléphones autorisés à se synchroniser',
                  icone: Icons.devices_rounded,
                  teinte: Color(0xFF0EA5E9),
                  child: AppareilsSection(isEmbedded: true),
                ),
              const SizedBox(height: Espace.lg),
            ],

            const _TitreGroupe('Assistant'),
            const _Volet(
              titre: 'Assistant IA & voix',
              sousTitre: 'Fournisseur, clé API, mode vocal, lecture',
              icone: Icons.auto_awesome_rounded,
              teinte: Color(0xFFA855F7),
              child: AssistantSection(isEmbedded: true),
            ),
            const SizedBox(height: Espace.lg),

            const _TitreGroupe('Appareil'),
            // Volontairement sans condition de droit : le verrou et
            // l'empreinte protègent le téléphone de celui qui le tient, pas
            // les données des autres.
            const _Volet(
              titre: 'Sécurité & verrouillage',
              sousTitre: 'Code à 6 chiffres, empreinte',
              icone: Icons.fingerprint_rounded,
              teinte: Color(0xFF10B981),
              child: SecuriteSection(),
            ),
            _Volet(
              titre: 'Apparence',
              sousTitre: switch (themeMode) {
                ThemeMode.light => 'Thème clair',
                ThemeMode.dark => 'Thème sombre',
                ThemeMode.system => 'Suit le système',
              },
              icone: Icons.palette_rounded,
              teinte: const Color(0xFFF59E0B),
              child: _ChoixTheme(
                courant: themeMode,
                onChange: (m) =>
                    ref.read(themeModeProvider.notifier).setThemeMode(m),
              ),
            ),
            _Volet(
              titre: 'Données & synchronisation',
              sousTitre: syncState.lastSync != null
                  ? 'Dernière synchro ${DateFormat('dd/MM HH:mm', 'fr_FR').format(syncState.lastSync!)}'
                  : 'Sauvegarde, synchronisation, restauration',
              icone: Icons.cloud_sync_rounded,
              teinte: const Color(0xFF3B82F6),
              badge: syncState.pendingCount > 0
                  ? '${syncState.pendingCount} en attente'
                  : null,
              badgeCouleur: context.metier.alerte,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppButton(
                    label: 'Forcer la synchronisation',
                    icon: Icons.sync_rounded,
                    onPressed: () =>
                        ref.read(syncEngineProvider).forceSyncCycle(),
                    isTonal: true,
                    expanded: true,
                  ),
                  const SizedBox(height: Espace.md),
                  // Sauvegarde et restauration complètes, avec aperçu du
                  // contenu avant d'écraser quoi que ce soit.
                  const SauvegardeSection(isEmbedded: true),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            const _TitreGroupe('Compte'),
            _Volet(
              titre: 'Mon compte',
              sousTitre: 'Mot de passe, déconnexion',
              icone: Icons.person_rounded,
              teinte: const Color(0xFF64748B),
              child: Column(
                children: [
                  _LigneAction(
                    icone: Icons.lock_outline_rounded,
                    libelle: 'Changer le mot de passe',
                    onTap: () => _changerMotDePasse(context, ref),
                  ),
                  // Le code de déverrouillage se change dans « Sécurité &
                  // verrouillage » : ici on ne toucherait que le code du
                  // serveur, et l'appareil garderait l'ancien.
                  _LigneAction(
                    icone: Icons.logout_rounded,
                    libelle: 'Se déconnecter',
                    danger: true,
                    onTap: () => _deconnexion(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.xl),

            Center(
              child: Text(
                'E.A.S Sarlu · version 1.0.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changerMotDePasse(BuildContext context, WidgetRef ref) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer le mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Ancien mot de passe'),
            ),
            const SizedBox(height: Espace.sm),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Nouveau mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          AppButton(
            label: 'Valider',
            onPressed: () async {
              try {
                await ref
                    .read(authRepositoryProvider)
                    .changePassword(oldCtrl.text, newCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mot de passe modifié')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erreur: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _deconnexion(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          AppButton(
            label: 'Déconnexion',
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(authStateProvider.notifier).logout();
      if (context.mounted) context.goNamed('auth-gate');
    }
  }
}

// ─── Les briques de la page ───────────────────────────────────────────────────

/// Le compte connecté, en tête : qui je suis, et si le téléphone est à jour.
class _EnTeteCompte extends StatelessWidget {
  final String initiales;
  final String nom;
  final String email;
  final bool synchro;
  final int enAttente;

  const _EnTeteCompte({
    required this.initiales,
    required this.nom,
    required this.email,
    required this.synchro,
    required this.enAttente,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Espace.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Rayon.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.7)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            alignment: Alignment.center,
            child: Text(
              initiales,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: Espace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: Espace.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(Rayon.pilule),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        synchro
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_upload_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        synchro ? 'À jour' : '$enAttente à envoyer',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitreGroupe extends StatelessWidget {
  final String texte;
  const _TitreGroupe(this.texte);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: Espace.sm),
      child: Text(
        texte.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Une rubrique des réglages, repliée par défaut.
///
/// Les paramètres tiennent sur une page de plus de dix sujets : tout afficher
/// d'un bloc obligeait à faire défiler pour trouver « où change-t-on le mot de
/// passe ». Chaque sujet est donc un volet qu'on ouvre. La tuile d'icône a sa
/// couleur propre : on repère la rubrique avant d'avoir lu son titre.
class _Volet extends StatefulWidget {
  final String titre;
  final String? sousTitre;
  final IconData icone;
  final Color teinte;
  final Widget child;
  final String? badge;
  final Color? badgeCouleur;

  const _Volet({
    required this.titre,
    this.sousTitre,
    required this.icone,
    required this.teinte,
    required this.child,
    this.badge,
    this.badgeCouleur,
  });

  @override
  State<_Volet> createState() => _VoletState();
}

class _VoletState extends State<_Volet> {
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Espace.sm),
      child: AnimatedContainer(
        duration: Duree.moyenne,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Rayon.lg),
          border: Border.all(
            color: _ouvert
                ? widget.teinte.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _ouvert = !_ouvert),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Espace.md, Espace.md, Espace.md, Espace.md),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.teinte.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(Rayon.md),
                      ),
                      child: Icon(widget.icone, color: widget.teinte, size: 22),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.titre,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.sousTitre != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.sousTitre!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.badge != null) ...[
                      const SizedBox(width: Espace.xs),
                      BadgePastille(
                        texte: widget.badge!,
                        couleur: widget.badgeCouleur ?? widget.teinte,
                      ),
                    ],
                    const SizedBox(width: Espace.xs),
                    AnimatedRotation(
                      turns: _ouvert ? 0.5 : 0,
                      duration: Duree.moyenne,
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: Duree.moyenne,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _ouvert
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Espace.page, 0, Espace.page, Espace.page),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(
                            height: 1,
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: Espace.md),
                          widget.child,
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne cliquable dans un volet.
class _LigneAction extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final bool danger;
  final VoidCallback onTap;

  const _LigneAction({
    required this.icone,
    required this.libelle,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = danger ? scheme.error : scheme.onSurface;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Rayon.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rayon.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Icon(icone, color: danger ? scheme.error : scheme.primary,
                  size: 22),
              const SizedBox(width: Espace.md),
              Expanded(
                child: Text(
                  libelle,
                  style: TextStyle(
                    color: couleur,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.outline, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le thème, en trois tuiles plutôt qu'en boutons segmentés : on voit ce
/// qu'on choisit.
class _ChoixTheme extends StatelessWidget {
  final ThemeMode courant;
  final ValueChanged<ThemeMode> onChange;
  const _ChoixTheme({required this.courant, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = [
      (ThemeMode.light, 'Clair', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Sombre', Icons.dark_mode_rounded),
      (ThemeMode.system, 'Auto', Icons.brightness_auto_rounded),
    ];
    return Row(
      children: [
        for (final (mode, libelle, icone) in options) ...[
          Expanded(
            child: Material(
              color: courant == mode
                  ? scheme.primary.withValues(alpha: 0.12)
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Rayon.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onChange(mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Rayon.md),
                    border: Border.all(
                      color: courant == mode
                          ? scheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(icone,
                          color: courant == mode
                              ? scheme.primary
                              : scheme.onSurfaceVariant),
                      const SizedBox(height: 6),
                      Text(
                        libelle,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: courant == mode
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (mode != ThemeMode.system) const SizedBox(width: Espace.sm),
        ],
      ],
    );
  }
}
