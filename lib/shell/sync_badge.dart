import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/db/app_database.dart' show Conflit;
import '../core/sync/sync_state.dart';
import '../core/sync/op_queue.dart';
import '../core/sync/conflit_sheet.dart';
import '../core/sync/sync_engine.dart';
import '../app/theme.dart';
import '../app/ui_kit.dart';

class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncStateProvider);
    final pendingCount = syncState.pendingCount;
    // Les conflits sont conservés en base, plusieurs à la fois : l'ancien
    // emplacement unique en mémoire n'en gardait qu'un, et les autres
    // disparaissaient sans que personne ne les voie.
    final conflits = ref.watch(conflitsProvider).valueOrNull ?? const [];

    Widget icon;
    String tooltip;
    Color color;

    if (conflits.isNotEmpty) {
      icon = const Icon(Icons.warning_amber);
      tooltip = conflits.length == 1
          ? 'Un conflit à arbitrer'
          : '${conflits.length} conflits à arbitrer';
      color = Colors.orange;
    } else if (syncState.status == SyncStatus.offline) {
      icon = const Icon(Icons.cloud_off);
      tooltip = 'Hors ligne — $pendingCount opération(s) en attente';
      color = Colors.red;
    } else if (syncState.status == SyncStatus.error ||
        syncState.errorMessage != null) {
      icon = const Icon(Icons.cloud_off);
      tooltip = syncState.errorMessage != null
          ? 'Erreur : ${syncState.errorMessage}'
          : 'Erreur de synchronisation ($pendingCount en attente)';
      color = Colors.red;
    } else if (pendingCount > 0) {
      icon = const Icon(Icons.cloud_off);
      tooltip = 'Non synchronisé — $pendingCount en attente';
      color = Colors.red;
    } else {
      icon = const Icon(Icons.cloud_done);
      tooltip = 'Synchronisé';
      color = Colors.green;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          if (conflits.isNotEmpty) {
            _showConflictSheet(context, conflits.first);
          } else {
            _showQueueSheet(context, ref);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IconTheme(data: IconThemeData(color: color), child: icon),
        ),
      ),
    );
  }

  void _showConflictSheet(BuildContext context, Conflit conflit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      builder: (_) => ConflictSheet(conflit: conflit),
    );
  }

  void _showQueueSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      builder: (_) => const QueueSheet(),
    );
  }
}

class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opsAsync = ref.watch(pendingOperationsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.vertical(top: Radius.circular(Rayon.xl)),
          ),
          child: Column(
            children: [
              // Poignée (Drag handle)
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(Rayon.xl),
                ),
              ),
              
              // En-tête
              Padding(
                padding: const EdgeInsets.fromLTRB(Espace.xl, Espace.lg, Espace.xl, Espace.md),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.sync_rounded, color: scheme.primary),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Synchronisation',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'File d\'attente des opérations',
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
              const Divider(height: 1),
              
              // Liste des opérations
              Expanded(
                child: opsAsync.when(
                  data: (ops) {
                    if (ops.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(Espace.xl),
                        child: EtatVide(
                          icone: Icons.cloud_done_rounded,
                          message: 'Tout est synchronisé !',
                          description: 'Aucune opération en attente. Vos données sont à jour avec le serveur.',
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(Espace.md),
                      itemCount: ops.length,
                      separatorBuilder: (_, __) => const SizedBox(height: Espace.sm),
                      itemBuilder: (context, index) {
                        final op = ops[index];
                        final estErreur = op.bloquee || op.dernierErreur != null;
                        final color = estErreur ? scheme.error : scheme.primary;

                        return AppCard(
                          padding: const EdgeInsets.all(Espace.md),
                          margin: EdgeInsets.zero,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(Rayon.md),
                                ),
                                child: Icon(
                                  op.bloquee ? Icons.sync_problem_rounded : Icons.cloud_upload_rounded,
                                  color: color,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: Espace.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _typeLisible(op.type),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tentative ${op.tentatives} • ${op.timestamp.substring(11, 16)}'
                                      '${op.bloquee ? ' • Suspendue' : ''}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (op.dernierErreur != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        op.dernierErreur!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.error,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ]
                                  ],
                                ),
                              ),
                              if (op.bloquee)
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded),
                                  color: scheme.primary,
                                  tooltip: 'Réessayer',
                                  style: IconButton.styleFrom(
                                    backgroundColor: scheme.primary.withValues(alpha: 0.1),
                                  ),
                                  onPressed: () {
                                    ref.read(opQueueProvider).reprendre(op.id);
                                    ref.read(syncEngineProvider).demanderSynchro();
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('Erreur: $e', style: TextStyle(color: scheme.error)),
                  ),
                ),
              ),

              // Bouton Forcer
              Container(
                padding: const EdgeInsets.all(Espace.lg),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: AppButton(
                    label: 'Forcer la synchronisation',
                    icon: Icons.sync_rounded,
                    onPressed: () {
                      ref.read(syncEngineProvider).forceSyncCycle();
                      Navigator.pop(context);
                    },
                    expanded: true,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _typeLisible(String type) {
    switch (type) {
      case 'vente':
        return 'Vente';
      case 'client':
        return 'Client';
      case 'article':
        return 'Article';
      case 'mouvement':
        return 'Mouvement de stock';
      case 'facture_paiement':
        return 'Paiement facture';
      case 'depense':
        return 'Dépense';
      case 'depense_reglement':
        return 'Règlement dépense';
      default:
        return type;
    }
  }
}
