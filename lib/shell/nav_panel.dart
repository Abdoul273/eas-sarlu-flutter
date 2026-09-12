// lib/shell/nav_panel.dart
//
// Panneau latéral ouvert par le menu hamburger. Il regroupe toutes les
// destinations principales et secondaires avec le design de marque.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.dart' show ouvrirRoute;

import '../app/theme.dart';
import '../app/ui_kit.dart';
import '../core/auth/auth_state.dart';
import '../core/sync/sync_state.dart';

/// Une entrée du panneau.
class EntreePanneau {
  final IconData icone;
  final String libelle;
  final String routeName;
  final String routePath;
  final String? description;

  /// Le droit qu'il faut détenir pour voir cette entrée. Nul, elle est ouverte
  /// à tous. Ce n'est qu'un masquage : le serveur refuse de toute façon les
  /// opérations non permises, mais proposer un écran qui ne donnera rien est
  /// une promesse qu'on ne tient pas.
  final String? droit;

  const EntreePanneau({
    required this.icone,
    required this.libelle,
    this.droit,
    required this.routeName,
    required this.routePath,
    this.description,
  });
}

/// Un groupe d'entrées, avec son intitulé.
class GroupePanneau {
  final String titre;
  final List<EntreePanneau> entrees;

  const GroupePanneau({required this.titre, required this.entrees});
}

/// Liste complète des catégories du menu latéral.
const List<GroupePanneau> kGroupesPanneau = [
  GroupePanneau(
    titre: 'Navigation Principale',
    entrees: [
      EntreePanneau(
        icone: Icons.grid_view_rounded,
        libelle: 'Accueil',
        routeName: 'accueil',
        routePath: '/accueil',
        description: 'Tableau de bord principal',
      ),
      EntreePanneau(
        icone: Icons.point_of_sale_rounded,
        libelle: 'Ventes',
        routeName: 'ventes',
        routePath: '/ventes',
        description: 'Journal & nouvelles ventes',
      ),
      EntreePanneau(
        icone: Icons.inventory_2_rounded,
        libelle: 'Stock',
        routeName: 'stock',
        routePath: '/stock',
        description: 'Catalogue des articles',
      ),
      EntreePanneau(
        icone: Icons.receipt_long_rounded,
        libelle: 'Factures',
        routeName: 'factures',
        routePath: '/factures',
        description: 'Créances & factures émises',
      ),
      EntreePanneau(
        icone: Icons.people_alt_rounded,
        libelle: 'Clients',
        routeName: 'clients',
        routePath: '/clients',
        description: 'Répertoire des acheteurs',
      ),
      EntreePanneau(
        icone: Icons.handshake_rounded,
        libelle: 'Fournisseurs',
        routeName: 'fournisseurs',
        routePath: '/fournisseurs',
        description: 'Répertoire des fournisseurs',
      ),
    ],
  ),
  GroupePanneau(
    titre: 'Opérations',
    entrees: [
      EntreePanneau(
        icone: Icons.request_quote_outlined,
        libelle: 'Proformas',
        droit: 'vendre',
        routeName: 'proformas',
        routePath: '/proformas',
        description: 'Devis remis, à transformer en vente',
      ),
      EntreePanneau(
        icone: Icons.local_shipping_outlined,
        libelle: 'Bons de livraison',
        routeName: 'bons',
        routePath: '/bons',
        description: 'Préparer et suivre les livraisons',
      ),
      EntreePanneau(
        icone: Icons.payments_outlined,
        libelle: 'Dépenses',
        droit: 'depenses',
        routeName: 'depenses',
        routePath: '/depenses',
        description: 'Achats, charges et règlements',
      ),
    ],
  ),
  GroupePanneau(
    titre: 'Pilotage & Analyses',
    entrees: [
      EntreePanneau(
        icone: Icons.account_balance_wallet_outlined,
        libelle: 'Finances',
        droit: 'finances',
        routeName: 'finances',
        routePath: '/finances',
        description: 'Trésorerie et marges',
      ),
      EntreePanneau(
        icone: Icons.insert_chart_outlined,
        libelle: 'Rapports',
        droit: 'finances',
        routeName: 'rapports',
        routePath: '/rapports',
        description: 'Synthèses exportables en PDF',
      ),
      EntreePanneau(
        icone: Icons.history_rounded,
        libelle: 'Activité',
        routeName: 'activite',
        routePath: '/activite',
        description: 'Journal des opérations',
      ),
    ],
  ),
  GroupePanneau(
    titre: 'Outils & IA',
    entrees: [
      EntreePanneau(
        icone: Icons.calculate_outlined,
        libelle: 'Calculateur',
        routeName: 'calculateur',
        routePath: '/calculateur',
        description: 'Métrés et quantités',
      ),
      EntreePanneau(
        icone: Icons.auto_awesome_outlined,
        libelle: 'Assistant IA',
        routeName: 'assistant',
        routePath: '/assistant',
        description: 'Poser une question sur le magasin',
      ),
    ],
  ),
];

class NavPanel extends ConsumerWidget {
  final String routeActive;

  const NavPanel({super.key, required this.routeActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final utilisateur = ref.watch(authStateProvider).value?.user;

    // Le menu ne propose que ce que le compte a le droit d'ouvrir. Un groupe
    // dont toutes les entrées sont interdites disparaît avec son titre, plutôt
    // que de laisser une rubrique vide.
    final groupesVisibles = [
      for (final groupe in kGroupesPanneau)
        if (groupe.entrees.any((e) =>
            e.droit == null || (utilisateur?.aLeDroit(e.droit!) ?? false)))
          GroupePanneau(
            titre: groupe.titre,
            entrees: [
              for (final e in groupe.entrees)
                if (e.droit == null || (utilisateur?.aLeDroit(e.droit!) ?? false))
                  e,
            ],
          ),
    ];

    return Drawer(
      backgroundColor: scheme.surface,
      child: Column(
        children: [
          _EnTetePanneau(nom: utilisateur?.nom, email: utilisateur?.email),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Espace.sm,
                Espace.sm,
                Espace.sm,
                Espace.sm,
              ),
              children: [
                for (final groupe in groupesVisibles) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Espace.md,
                      Espace.md,
                      Espace.md,
                      Espace.xs,
                    ),
                    child: Text(
                      groupe.titre.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  for (final entree in groupe.entrees)
                    _TuilePanneau(
                      entree: entree,
                      actif: _estActif(routeActive, entree.routePath),
                      onTap: () => _naviguer(context, entree.routeName),
                    ),
                  const SizedBox(height: Espace.xs),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          _PiedPanneau(routeActive: routeActive),
        ],
      ),
    );
  }

  bool _estActif(String routeActive, String routePath) {
    if (routePath == '/accueil') {
      return routeActive == '/accueil' || routeActive == '/';
    }
    return routeActive.startsWith(routePath);
  }

  void _naviguer(BuildContext context, String routeName) {
    // Le tiroir se ferme d'abord, puis on navigue depuis le contexte du
    // shell : c'est lui qui connaît la route courante.
    final shell = Navigator.of(context).context;
    Navigator.of(context).pop();
    ouvrirRoute(shell, routeName);
  }
}

/// En-tête : dégradé de marque, identité de l'utilisateur, état de synchro.
class _EnTetePanneau extends ConsumerWidget {
  final String? nom;
  final String? email;

  const _EnTetePanneau({this.nom, this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nomAffiche =
        (nom == null || nom!.trim().isEmpty) ? 'Utilisateur' : nom!;
    final initiales = _initiales(nomAffiche);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, const Color(0xFFE85D04), 0.5)!,
            const Color(0xFFC23E00),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(Espace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(Rayon.md),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initiales,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: Espace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nomAffiche,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (email != null && email!.isNotEmpty)
                          Text(
                            email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Espace.md),
              // Aucun des deux enfants n'était flexible : à la police système
              // agrandie, la pastille de synchronisation poussait le nom hors
              // du panneau et la ligne débordait. Le nom cède la place en
              // premier — la pastille, elle, doit rester lisible en entier,
              // c'est elle qui dit si les ventes sont parties.
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'E.A.S Sarlu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: Espace.sm),
                  const Flexible(child: _PastilleSynchro()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initiales(String nom) {
    final parts =
        nom.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}

/// Pastille d'état de synchronisation affichée dans l'en-tête du panneau.
class _PastilleSynchro extends ConsumerWidget {
  const _PastilleSynchro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(syncStateProvider);

    late final String texte;
    late final IconData icone;
    switch (etat.status) {
      case SyncStatus.idle:
        texte = 'À jour';
        icone = Icons.cloud_done_rounded;
        break;
      case SyncStatus.syncing:
        texte = 'Synchro…';
        icone = Icons.sync_rounded;
        break;
      case SyncStatus.offline:
        texte = 'Hors ligne';
        icone = Icons.cloud_off_rounded;
        break;
      case SyncStatus.error:
        texte = 'Erreur';
        icone = Icons.error_outline_rounded;
        break;
      case SyncStatus.conflict:
        texte = 'Conflit';
        icone = Icons.warning_amber_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espace.sm + 2, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(Rayon.pilule),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 13, color: Colors.white),
          const SizedBox(width: Espace.xs + 1),
          // « Synchronisation… » à la police agrandie dépasse la largeur du
          // panneau : le libellé se resserre plutôt que de déborder.
          Flexible(
            child: Text(
              texte,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Entrée cliquable du panneau avec barre d'état active.
class _TuilePanneau extends StatelessWidget {
  final EntreePanneau entree;
  final bool actif;
  final VoidCallback onTap;

  const _TuilePanneau({
    required this.entree,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final couleur = actif ? scheme.primary : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: actif
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Rayon.md),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Rayon.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Rayon.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Espace.sm,
                vertical: Espace.sm + 2,
              ),
              child: Row(
                children: [
                  // Barre verticale indicateur actif
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 4,
                    height: 28,
                    decoration: BoxDecoration(
                      color: actif ? scheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(Rayon.pilule),
                    ),
                  ),
                  const SizedBox(width: Espace.sm),

                  // Icône dans un conteneur dédié
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: actif
                          ? scheme.primary.withValues(alpha: 0.15)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(Rayon.sm),
                    ),
                    child: Icon(entree.icone, size: 20, color: couleur),
                  ),
                  const SizedBox(width: Espace.md),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entree.libelle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                actif ? FontWeight.bold : FontWeight.w600,
                            color: actif ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                        if (entree.description != null)
                          Text(
                            entree.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (actif)
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pied de panneau : Paramètres & Déconnexion.
class _PiedPanneau extends ConsumerWidget {
  final String routeActive;

  const _PiedPanneau({required this.routeActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final metier = context.metier;
    final utilisateur = ref.watch(authStateProvider).value?.user;

    // Les Paramètres restent ouverts à tous : on y trouve son mot de passe, le
    // code de déverrouillage, le thème et l'assistant IA. Seules les sections
    // sensibles de la page sont gardées, une par une.
    final peutOuvrirParametres = utilisateur != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Espace.sm,
          Espace.sm,
          Espace.sm,
          Espace.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Les Paramètres ne s'affichent que s'ils mènent quelque part :
            // sans aucun droit d'administration, la page serait vide.
            if (peutOuvrirParametres) ...[
              _TuilePanneau(
                entree: const EntreePanneau(
                  icone: Icons.settings_outlined,
                  libelle: 'Paramètres',
                  routeName: 'parametres',
                  routePath: '/parametres',
                  description: 'Configuration du compte et de l\'app',
                ),
                actif: routeActive.startsWith('/parametres'),
                onTap: () {
                  final shell = Navigator.of(context).context;
                  Navigator.of(context).pop();
                  ouvrirRoute(shell, 'parametres');
                },
              ),
              const SizedBox(height: 2),
            ],
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(Rayon.md),
              child: InkWell(
                onTap: () => _confirmerDeconnexion(context, ref),
                borderRadius: BorderRadius.circular(Rayon.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Espace.md,
                    vertical: Espace.sm + 2,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: metier.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(Rayon.sm),
                        ),
                        child: Icon(Icons.logout_rounded,
                            size: 20, color: metier.danger),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Text(
                          'Se déconnecter',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: metier.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmerDeconnexion(
      BuildContext context, WidgetRef ref) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Les opérations non synchronisées resteront en attente sur cet appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          AppButton(
            label: 'Se déconnecter',
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    Navigator.of(context).pop();
    await ref.read(authStateProvider.notifier).logout();
  }
}
