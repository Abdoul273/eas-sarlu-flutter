// lib/shell/notification_badge.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../core/models/activite.dart';
import '../features/activite/activite_style.dart';
import '../features/activite/notifications_provider.dart';

/// Largeur du menu déroulant. Fixe pour que les lignes se coupent au même
/// endroit d'une notification à l'autre.
const double _largeurMenu = 320;

class NotificationBadge extends ConsumerStatefulWidget {
  const NotificationBadge({super.key});

  @override
  ConsumerState<NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends ConsumerState<NotificationBadge> {
  final MenuController _controleur = MenuController();

  /// Ce que l'on affiche dans le menu ouvert.
  ///
  /// Figé à l'ouverture, et non relu à chaque image : le menu est marqué comme
  /// lu dès qu'on l'ouvre, si bien qu'un menu branché sur l'état vivant se
  /// vidait sous les yeux de l'utilisateur et affichait « Aucune nouvelle
  /// notification » au moment précis où il venait les consulter.
  List<ActiviteEntree> _figees = const [];
  int _nonLuesFigees = 0;

  void _ouvrir() {
    final etat = ref.read(notificationsProvider);
    setState(() {
      _figees = etat.recentes;
      _nonLuesFigees = etat.nombreNonLues;
    });
    _controleur.open();
  }

  /// La lecture est enregistrée par `onClose` du `MenuAnchor`, quel que soit le
  /// geste qui referme le menu — clic sur la cloche, clic à côté, ou touche
  /// Échap. Marquer lu ici seulement laissait le badge allumé quand on
  /// refermait le menu en cliquant ailleurs.
  void _fermer() => _controleur.close();

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(notificationsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MenuAnchor(
      controller: _controleur,
      alignmentOffset: const Offset(-20, 10),
      onClose: () => ref.read(notificationsProvider.notifier).marquerLu(),
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
      builder: (context, controller, child) {
        final nombre = etat.nombreNonLues;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => controller.isOpen ? _fermer() : _ouvrir(),
              tooltip: nombre > 0
                  ? '$nombre nouvelle${nombre > 1 ? 's' : ''} activité${nombre > 1 ? 's' : ''}'
                  : 'Notifications',
              icon: Icon(
                controller.isOpen
                    ? Icons.notifications_rounded
                    : Icons.notifications_outlined,
                size: 26,
                color: controller.isOpen
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                backgroundColor: controller.isOpen
                    ? scheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
            ),
            // Le compte s'affiche dans la pastille plutôt qu'un simple point :
            // « trois choses à voir » et « une chose à voir » ne se décident
            // pas de la même façon.
            if (nombre > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(Rayon.xl),
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      nombre > 99 ? '99+' : '$nombre',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onError,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      menuChildren: [
        _EnTete(nonLues: _nonLuesFigees, permissionRefusee: etat.permissionRefusee),
        const Divider(height: 1),
        if (_figees.isEmpty)
          const _MenuVide()
        else
          // Le menu est borné en hauteur : sans cela, trente entrées
          // débordaient de l'écran et les deux dernières lignes — dont
          // « Voir tout l'historique » — devenaient inatteignables.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _figees.length; i++)
                    _LigneNotification(
                      activite: _figees[i],
                      nonLue: i < _nonLuesFigees,
                      onTap: () {
                        _fermer();
                        final destination = _figees[i].destination;
                        context.push(destination ?? '/activite');
                      },
                    ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),
        MenuItemButton(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: Espace.md)),
            backgroundColor:
                WidgetStatePropertyAll(scheme.surfaceContainerLowest),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(Rayon.xl)),
              ),
            ),
          ),
          onPressed: () => context.push('/activite'),
          child: SizedBox(
            width: _largeurMenu,
            child: Center(
              child: Text(
                "Voir tout l'historique",
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.nonLues, required this.permissionRefusee});

  final int nonLues;
  final bool permissionRefusee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: _largeurMenu,
      padding: const EdgeInsets.symmetric(
          horizontal: Espace.lg, vertical: Espace.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Rayon.xl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notifications',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (nonLues > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Rayon.xl),
                  ),
                  child: Text(
                    '$nonLues nouvelle${nonLues > 1 ? 's' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          // Sans cette ligne, un utilisateur qui a refusé la permission Android
          // croit à une panne : le badge se remplit, mais aucune bannière
          // n'arrive jamais quand l'application est fermée.
          if (permissionRefusee) ...[
            const SizedBox(height: Espace.xs),
            Text(
              'Les bannières système sont désactivées pour E.A.S Sarlu. '
              'Réglages Android → Notifications pour les réactiver.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuVide extends StatelessWidget {
  const _MenuVide();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: _largeurMenu,
      padding: const EdgeInsets.all(Espace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 48, color: scheme.surfaceContainerHighest),
          const SizedBox(height: Espace.md),
          Text(
            'Rien de neuf.\nVos propres saisies ne sont pas listées ici.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LigneNotification extends StatelessWidget {
  const _LigneNotification({
    required this.activite,
    required this.nonLue,
    required this.onTap,
  });

  final ActiviteEntree activite;
  final bool nonLue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final couleur = couleurActivite(context, activite.type);
    final date = activite.dateTime;

    return MenuItemButton(
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      onPressed: onTap,
      child: Container(
        width: _largeurMenu,
        padding: const EdgeInsets.symmetric(
            horizontal: Espace.lg, vertical: Espace.md),
        decoration: BoxDecoration(
          color: nonLue
              ? scheme.primary.withValues(alpha: 0.04)
              : scheme.surfaceContainerLowest,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(iconeActivite(activite.type),
                  color: couleur, size: 20),
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
                      fontWeight: nonLue ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          activite.auteur,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (date != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _quand(date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
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

  /// Heure pour aujourd'hui, date sinon. Une notification d'il y a trois jours
  /// affichée « 14:05 » se lit comme si elle venait d'arriver.
  static String _quand(DateTime date) {
    final maintenant = DateTime.now();
    final memeJour = date.year == maintenant.year &&
        date.month == maintenant.month &&
        date.day == maintenant.day;
    return memeJour
        ? DateFormat('HH:mm').format(date)
        : DateFormat('d MMM', 'fr_FR').format(date);
  }
}
