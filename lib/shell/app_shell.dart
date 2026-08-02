// lib/shell/app_shell.dart
//
// Coque de l'application : barre du haut, panneau latéral (hamburger),
// barre de navigation basse flottante et bouton flottant contextuel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_state.dart';
import '../core/sync/sync_state.dart';
import '../app/theme.dart';
import '../features/clients/client_form_sheet.dart';
import '../features/fournisseurs/fournisseur_form_sheet.dart';
import 'nav_panel.dart';
import 'sync_badge.dart';
import 'notification_badge.dart';

/// Une destination de la barre de navigation basse.
class _Destination {
  final IconData icone;
  final IconData iconeActive;
  final String libelle;
  final String routeName;
  final String routePath;

  const _Destination({
    required this.icone,
    required this.iconeActive,
    required this.libelle,
    required this.routeName,
    required this.routePath,
  });
}

const List<_Destination> _destinations = [
  _Destination(
    icone: Icons.grid_view_outlined,
    iconeActive: Icons.grid_view_rounded,
    libelle: 'Accueil',
    routeName: 'accueil',
    routePath: '/accueil',
  ),
  _Destination(
    icone: Icons.point_of_sale_outlined,
    iconeActive: Icons.point_of_sale_rounded,
    libelle: 'Ventes',
    routeName: 'ventes',
    routePath: '/ventes',
  ),
  _Destination(
    icone: Icons.inventory_2_outlined,
    iconeActive: Icons.inventory_2_rounded,
    libelle: 'Stock',
    routeName: 'stock',
    routePath: '/stock',
  ),
  _Destination(
    icone: Icons.receipt_long_outlined,
    iconeActive: Icons.receipt_long_rounded,
    libelle: 'Factures',
    routeName: 'factures',
    routePath: '/factures',
  ),
  _Destination(
    icone: Icons.people_alt_outlined,
    iconeActive: Icons.people_alt_rounded,
    libelle: 'Clients',
    routeName: 'clients',
    routePath: '/clients',
  ),
];

class AppShell extends ConsumerWidget {
  final String title;
  final Widget child;

  const AppShell({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).uri.path;
    final index = _indexDepuisRoute(location);

    // Une opération refusée par le serveur faute de droit ne repartira pas, et
    // l'écran a déjà repris l'état du serveur. Mais quelqu'un a saisi quelque
    // chose qui n'a pas été retenu : le lui taire serait le laisser croire que
    // sa vente est enregistrée.
    ref.listen(syncStateProvider.select((e) => e.refus), (_, refus) {
      if (refus.isEmpty) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: theme.colorScheme.error,
        content: Text(
          refus.length == 1
              ? refus.first
              : '${refus.length} opérations refusées :\n${refus.join('\n')}',
          style: TextStyle(color: theme.colorScheme.onError),
        ),
      ));
      ref.read(syncStateProvider.notifier).accuserReceptionRefus();
    });

    // Le serveur n'accepte plus la session. L'application reste utilisable —
    // les données du téléphone sont là, la file d'attente est intacte — mais il
    // faut le dire : jusqu'ici l'état était bien calculé et n'apparaissait
    // nulle part, si bien qu'on pouvait saisir des ventes toute la journée sans
    // savoir qu'elles ne partiraient pas.
    ref.listen<({bool expiree, String? motif})>(
      authStateProvider.select((e) => (
            expiree: e.value?.sessionExpiree ?? false,
            motif: e.value?.motifDeconnexion,
          )),
      (avant, apres) {
        // Seulement au passage à « expirée » : sans cela le message reviendrait
        // à chaque reconstruction de la coque.
        if (!apres.expiree || (avant?.expiree ?? false)) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 12),
          backgroundColor: theme.colorScheme.error,
          content: Text(
            apres.motif ??
                'Votre session a expiré. Reconnectez-vous pour synchroniser.',
            style: TextStyle(color: theme.colorScheme.onError),
          ),
        ));
      },
    );

    return Scaffold(
      extendBody: true,
      drawer: NavPanel(routeActive: location),
      drawerEdgeDragWidth: 44,
      drawerScrimColor: Colors.black.withValues(alpha: 0.55),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: Espace.sm),
            child: IconButton(
              icon: const Icon(Icons.menu_rounded, size: 24),
              tooltip: 'Ouvrir le menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        leadingWidth: 56,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        actions: const [
          SyncBadge(),
          SizedBox(width: Espace.xs),
          NotificationBadge(),
          SizedBox(width: Espace.xs),
          _ThemeToggle(),
          SizedBox(width: Espace.sm),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      body: child,
      bottomNavigationBar: _BarreNavigationFlottante(
        index: index,
        onSelect: (i) => context.goNamed(_destinations[i].routeName),
      ),
      floatingActionButton: _buildFab(context, ref, location),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  int _indexDepuisRoute(String location) {
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].routePath)) return i;
    }
    return 0;
  }

  Widget? _buildFab(BuildContext context, WidgetRef ref, String location) {
    final scheme = Theme.of(context).colorScheme;
    const marginBas = EdgeInsets.only(bottom: 0);
    final utilisateur = ref.watch(authStateProvider).value?.user;

    if (location.startsWith('/clients')) {
      return Container(
        margin: marginBas,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rayon.lg),
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, Colors.orangeAccent, 0.3)!
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'fab-nouveau-client',
          tooltip: 'Nouveau client',
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          onPressed: () {
            showModalBottomSheet(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              showDragHandle: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              builder: (_) => const ClientFormSheet(),
            );
          },
          child:
              const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        ),
      );
    }
    if (location.startsWith('/fournisseurs')) {
      return Container(
        margin: marginBas,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rayon.lg),
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, Colors.orangeAccent, 0.3)!
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'fab-nouveau-fournisseur',
          tooltip: 'Nouveau fournisseur',
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          onPressed: () {
            showModalBottomSheet(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              showDragHandle: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              builder: (_) => const FournisseurFormSheet(),
            );
          },
          child:
              const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        ),
      );
    }
    if (location.startsWith('/ventes')) {
      return Container(
        margin: marginBas,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rayon.lg),
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, Colors.orangeAccent, 0.3)!
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'fab-nouvelle-vente',
          tooltip: 'Nouvelle vente',
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          onPressed: () => context.pushNamed('nouvelle-vente'),
          child:
              const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        ),
      );
    }
    if (location.startsWith('/accueil')) {
      return Container(
        margin: marginBas,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rayon.pilule),
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, Colors.orangeAccent, 0.3)!
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          heroTag: 'fab-accueil-vente',
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          onPressed: () => context.pushNamed('nouvelle-vente'),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text(
            'Nouvelle vente',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    // La page Stock reste ouverte à tous — consulter le catalogue et vérifier
    // ce qu'il reste est le geste le plus courant du comptoir. Créer un article
    // exige en revanche le droit d'écrire dessus, que le serveur vérifie de son
    // côté : ouvrir le formulaire sans ce droit ne mènerait qu'à un refus au
    // moment d'enregistrer, après la saisie.
    if (location.startsWith('/stock') &&
        (utilisateur?.aLeDroit('stock') ?? false)) {
      return Container(
        margin: marginBas,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rayon.lg),
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, Colors.orangeAccent, 0.3)!
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'fab-nouvel-article',
          tooltip: 'Nouvel article',
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          onPressed: () => context.pushNamed('nouvel-article'),
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      );
    }
    return null;
  }
}

/// Barre de navigation basse flottante ultra moderne (Floating Island style).
class _BarreNavigationFlottante extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _BarreNavigationFlottante({
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sombre = scheme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        height: 64,
        decoration: BoxDecoration(
          color: sombre
              ? scheme.surfaceContainerLowest.withValues(alpha: 0.94)
              : Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: sombre ? 0.6 : 0.8),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: sombre
                  ? Colors.black.withValues(alpha: 0.45)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: _ItemNavigationFlottant(
                  destination: _destinations[i],
                  actif: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemNavigationFlottant extends StatelessWidget {
  final _Destination destination;
  final bool actif;
  final VoidCallback onTap;

  const _ItemNavigationFlottant({
    required this.destination,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = actif ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      selected: actif,
      button: true,
      label: destination.libelle,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: Duree.rapide,
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(
                horizontal: Espace.md,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: actif
                    ? scheme.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(Rayon.pilule),
              ),
              child: Icon(
                actif ? destination.iconeActive : destination.icone,
                size: 22,
                color: couleur,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  destination.libelle,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: actif ? FontWeight.w800 : FontWeight.w500,
                    color: couleur,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton de bascule de thème clair / sombre (Theme Mode Toggle) dans l'AppBar.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return IconButton(
      icon: AnimatedSwitcher(
        duration: Duree.rapide,
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(isDark),
          color: isDark
              ? const Color(0xFFFFB703)
              : Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      tooltip: isDark ? 'Passer en mode clair' : 'Passer en mode sombre',
      onPressed: () {
        final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
        ref.read(themeModeProvider.notifier).setThemeMode(newMode);
      },
    );
  }
}
