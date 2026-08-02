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
          padding: const EdgeInsets.all(Espace.page),
          children: [
            // Chaque section n'apparaît qu'à qui a le droit d'y toucher. Le
            // serveur refuse de toute façon les écritures ; ce masquage évite
            // d'ouvrir un formulaire dont l'enregistrement échouera.

            // 1. Conteneur Rétractable : FICHE ENTREPRISE
            if (user?.aLeDroit('entreprise') ?? false) ...[
              const _ConteneurRetractableCard(
                title: 'Fiche Entreprise',
                subtitle: 'Logo, nom, NIF, RCCM, coordonnées & banque',
                icon: Icons.business_rounded,
                initiallyExpanded: true,
                child: EntrepriseForm(isEmbedded: true),
              ),
              const SizedBox(height: Espace.md),
            ],

            // 2. Conteneur Rétractable : GESTION DES UTILISATEURS
            if (user?.aLeDroit('utilisateurs') ?? false) ...[
              const _ConteneurRetractableCard(
                title: 'Utilisateurs & Droits d\'Accès',
                subtitle: 'Gestion des comptes d\'utilisateurs du magasin',
                icon: Icons.people_rounded,
                initiallyExpanded: false,
                child: UtilisateursSection(isEmbedded: true),
              ),
              const SizedBox(height: Espace.md),
            ],

            // 3. Conteneur Rétractable : SÉCURITÉ DE L'APPAREIL
            // Volontairement sans condition de droit : le verrou et l'empreinte
            // protègent le téléphone de celui qui le tient, pas les données des
            // autres. Un compte sans aucun droit pose le même téléphone sur le
            // même comptoir et doit pouvoir régler les deux.
            const _ConteneurRetractableCard(
              title: 'Sécurité & Verrouillage',
              subtitle: 'Code à 6 chiffres et déverrouillage par empreinte',
              icon: Icons.fingerprint_rounded,
              initiallyExpanded: false,
              child: SecuriteSection(),
            ),
            const SizedBox(height: Espace.md),

            // 4. Conteneur Rétractable : ASSISTANT IA
            const _ConteneurRetractableCard(
              title: 'Assistant IA & Voix',
              subtitle: 'Fournisseur, clé API, lecture à voix haute',
              icon: Icons.auto_awesome_rounded,
              initiallyExpanded: false,
              child: AssistantSection(isEmbedded: true),
            ),
            const SizedBox(height: Espace.md),

            // 5. Conteneur Rétractable : APPAREILS DE CONFIANCE
            if (user?.aLeDroit('appareils') ?? false) ...[
              const _ConteneurRetractableCard(
                title: 'Appareils de Confiance',
                subtitle: 'Terminaux et téléphones autorisés à se synchroniser',
                icon: Icons.devices_rounded,
                initiallyExpanded: false,
                child: AppareilsSection(isEmbedded: true),
              ),
              const SizedBox(height: Espace.md),
            ],

            // 6. Conteneur Rétractable : MON COMPTE
            _ConteneurRetractableCard(
              title: 'Mon Compte',
              subtitle: user?.email ?? 'Informations personnelles et mot de passe',
              icon: Icons.person_pin_rounded,
              initiallyExpanded: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initiales,
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.nom ?? 'Utilisateur',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              user?.email ?? 'Connecté',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espace.md),
                  const Divider(height: 1),
                  const SizedBox(height: Espace.xs),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline_rounded,
                        color: scheme.primary),
                    title: const Text('Changer le mot de passe'),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: scheme.outline),
                    onTap: () => _changerMotDePasse(context, ref),
                  ),
                  // Le code de déverrouillage se change dans « Sécurité &
                  // Verrouillage ». L'entrée qui vivait ici n'écrivait que le
                  // code du serveur : le verrou local restait sur l'ancien, et
                  // l'appareil se retrouvait avec deux codes différents.
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout_rounded, color: scheme.error),
                    title: Text(
                      'Se déconnecter',
                      style: TextStyle(
                          color: scheme.error, fontWeight: FontWeight.bold),
                    ),
                    onTap: () => _deconnexion(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.md),

            // 7. Conteneur Rétractable : APPARENCE & THÈME
            _ConteneurRetractableCard(
              title: 'Apparence & Thème',
              subtitle: 'Mode clair, sombre ou automatique',
              icon: Icons.palette_rounded,
              initiallyExpanded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SÉLECTIONNEZ LE THÈME DE L\'APPLICATION',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: Espace.sm),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        label: Text('Clair'),
                        icon: Icon(Icons.light_mode_rounded),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        label: Text('Sombre'),
                        icon: Icon(Icons.dark_mode_rounded),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        label: Text('Système'),
                        icon: Icon(Icons.settings_suggest_rounded),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (vals) {
                      ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(vals.first);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.md),

            // 8. Conteneur Rétractable : DONNÉES & SYNCHRONISATION
            _ConteneurRetractableCard(
              title: 'Données & Synchronisation',
              subtitle: 'Sauvegarde locale, synchronisation distante et réinitialisation',
              icon: Icons.sync_rounded,
              badgeText: syncState.pendingCount > 0
                  ? '${syncState.pendingCount} en attente'
                  : null,
              badgeColor: syncState.pendingCount > 0
                  ? context.metier.alerte
                  : context.metier.succes,
              initiallyExpanded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.metier.succes.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(Rayon.sm),
                        ),
                        child: Icon(Icons.cloud_done_rounded,
                            color: context.metier.succes),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dernière synchronisation',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              syncState.lastSync != null
                                  ? DateFormat('dd/MM/yyyy HH:mm', 'fr_FR')
                                      .format(syncState.lastSync!)
                                  : 'Aucune récente',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      BadgePastille(
                        texte: '${syncState.pendingCount} en attente',
                        couleur: syncState.pendingCount > 0
                            ? context.metier.alerte
                            : context.metier.succes,
                      ),
                    ],
                  ),
                  const SizedBox(height: Espace.md),
                  AppButton(
                    label: 'Forcer la synchronisation',
                    icon: Icons.sync_rounded,
                    onPressed: () =>
                        ref.read(syncEngineProvider).forceSyncCycle(),
                    isTonal: true,
                    expanded: true,
                  ),
                  const SizedBox(height: Espace.sm),
                  const Divider(height: 1),
                  const SizedBox(height: Espace.xs),
                  // Sauvegarde et restauration complètes, avec aperçu du
                  // contenu avant d'écraser quoi que ce soit. Remplace les deux
                  // anciennes entrées, qui partaient sans rien montrer.
                  const SauvegardeSection(isEmbedded: true),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            // Carte À Propos
            AppCard(
              margin: EdgeInsets.zero,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Espace.sm),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Rayon.sm),
                    ),
                    child: Icon(Icons.info_outline_rounded,
                        color: scheme.primary),
                  ),
                  const SizedBox(width: Espace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'E.A.S Sarlu',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Gestion de magasin • Version 1.0.0',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80),
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

/// Une rubrique des réglages, repliée par défaut.
///
/// Les paramètres tiennent sur une page de plus de dix sujets : tout afficher
/// d'un bloc obligeait à faire défiler pour trouver « où change-t-on le mot de
/// passe ». Chaque sujet est donc un volet qu'on ouvre.
class _ConteneurRetractableCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool initiallyExpanded;
  final Widget child;

  /// Pastille affichée à droite du titre — « 3 en attente », par exemple : ce
  /// qui mérite d'être vu sans ouvrir le volet.
  final String? badgeText;
  final Color? badgeColor;

  const _ConteneurRetractableCard({
    required this.title,
    this.subtitle,
    required this.icon,
    this.initiallyExpanded = false,
    this.badgeText,
    this.badgeColor,
    required this.child,
  });

  @override
  State<_ConteneurRetractableCard> createState() =>
      __ConteneurRetractableCardState();
}

class __ConteneurRetractableCardState
    extends State<_ConteneurRetractableCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Rayon.md),
        border: Border.all(
          color: _expanded
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (exp) => setState(() => _expanded = exp),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _expanded
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: 20,
              color: _expanded ? scheme.onPrimary : scheme.primary,
            ),
          ),
          title: Text(
            widget.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: _expanded ? scheme.primary : scheme.onSurface,
            ),
          ),
          subtitle: widget.subtitle != null
              ? Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.badgeText != null) ...[
                BadgePastille(
                  texte: widget.badgeText!,
                  couleur: widget.badgeColor ?? scheme.primary,
                ),
                const SizedBox(width: Espace.xs),
              ],
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _expanded ? scheme.primary : scheme.outline,
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.all(Espace.page),
          children: [
            const Divider(height: 1),
            const SizedBox(height: Espace.md),
            widget.child,
          ],
        ),
      ),
    );
  }
}
