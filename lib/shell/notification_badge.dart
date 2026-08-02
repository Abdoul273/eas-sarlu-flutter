import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../features/activite/activite_page.dart';
import '../../features/activite/notifications_provider.dart';
import '../../core/models/models.dart';

class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsState = ref.watch(notificationsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MenuAnchor(
      alignmentOffset: const Offset(-20, 10), // Pousse le menu vers la droite (aligné avec la cloche)
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        elevation: const WidgetStatePropertyAll(12),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rayon.xl),
            side: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      builder: (BuildContext context, MenuController controller, Widget? child) {
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                  ref.read(notificationsProvider.notifier).markAllAsRead();
                }
              },
              tooltip: 'Notifications',
              icon: Icon(
                controller.isOpen ? Icons.notifications_rounded : Icons.notifications_outlined,
                size: 26,
                color: controller.isOpen ? scheme.primary : scheme.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                backgroundColor: controller.isOpen ? scheme.primary.withValues(alpha: 0.1) : Colors.transparent,
              ),
            ),
            if (notifsState.hasUnread)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.surface,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.error.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 12,
                    minHeight: 12,
                  ),
                ),
              ),
          ],
        );
      },
      menuChildren: [
        // En-tête
        Container(
          width: 320, // Largeur fixe de la popup
          padding: const EdgeInsets.symmetric(horizontal: Espace.lg, vertical: Espace.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Rayon.xl)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notifications',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (notifsState.unreadActivities.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Rayon.xl),
                  ),
                  child: Text(
                    '${notifsState.unreadActivities.length} nlles',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        
        // Contenu
        if (notifsState.unreadActivities.isEmpty)
          Container(
            width: 320,
            padding: const EdgeInsets.all(Espace.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_active_outlined, size: 48, color: scheme.surfaceContainerHighest),
                const SizedBox(height: Espace.md),
                Text(
                  'Aucune nouvelle notification',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...notifsState.unreadActivities.map((activite) => _NotificationItem(activite: activite)),

        // Pied de page
        const Divider(height: 1),
        MenuItemButton(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Espace.md)),
            backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Rayon.xl)),
              ),
            ),
          ),
          onPressed: () {
            context.goNamed('activite');
          },
          child: Center(
            child: Text(
              'Voir tout l\'historique',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final ActiviteEntree activite;

  const _NotificationItem({required this.activite});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    // Déterminer l'icône et la couleur selon le type d'activité
    IconData icon;
    Color iconColor;
    
    switch (activite.type) {
      case 'vente':
        icon = Icons.point_of_sale_rounded;
        iconColor = Colors.green;
        break;
      case 'depense':
        icon = Icons.money_off_rounded;
        iconColor = Colors.red;
        break;
      case 'client':
        icon = Icons.person_rounded;
        iconColor = Colors.blue;
        break;
      case 'stock':
        icon = Icons.inventory_2_rounded;
        iconColor = Colors.orange;
        break;
      case 'facture':
        icon = Icons.receipt_long_rounded;
        iconColor = Colors.purple;
        break;
      default:
        icon = Icons.info_outline_rounded;
        iconColor = scheme.primary;
    }

    return MenuItemButton(
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      onPressed: () {
        context.goNamed('activite');
      },
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: Espace.lg, vertical: Espace.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: Espace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activite.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          activite.auteur,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (activite.dateTime != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('HH:mm').format(activite.dateTime!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
