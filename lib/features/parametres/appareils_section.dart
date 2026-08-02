import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';

// Provider pour la liste des appareils
final appareilsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get(kDataDevices);
  return List<Map<String, dynamic>>.from(response.data);
});

class AppareilsSection extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const AppareilsSection({super.key, this.isEmbedded = false});

  @override
  ConsumerState<AppareilsSection> createState() => _AppareilsSectionState();
}

class _AppareilsSectionState extends ConsumerState<AppareilsSection> {
  Future<String?> _getDeviceId() async {
    final authRepo = ref.read(authRepositoryProvider);
    return await authRepo.getDeviceId();
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appareilsAsync = ref.watch(appareilsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TERMINAUX AUTORISÉS',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: Espace.xs),
        FutureBuilder<String?>(
          future: _getDeviceId(),
          builder: (context, snapshot) {
            final currentDeviceId = snapshot.data;
            return appareilsAsync.when(
              data: (appareils) {
                if (appareils.isEmpty) {
                  return const EtatVide(
                    message: 'Aucun appareil de confiance enregistré',
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: appareils.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Espace.xs),
                  itemBuilder: (context, index) {
                    final appareil = appareils[index];
                    final isCurrent = appareil['id'] == currentDeviceId;
                    final comptes = (appareil['comptes'] as List?)
                            ?.map((c) => c['nom'])
                            .join(', ') ??
                        '';

                    return AppCard(
                      margin: EdgeInsets.zero,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? context.metier.succes
                                      .withValues(alpha: 0.12)
                                  : scheme.surfaceContainerHigh,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.phone_android_rounded,
                              size: 20,
                              color: isCurrent
                                  ? context.metier.succes
                                      : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: Espace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        appareil['nom'] ??
                                            'Appareil ${index + 1}',
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (isCurrent)
                                      BadgePastille(
                                        texte: 'Cet appareil',
                                        couleur: context.metier.succes,
                                      ),
                                  ],
                                ),
                                if (comptes.isNotEmpty)
                                  Text(
                                    'Comptes associés : $comptes',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!isCurrent)
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded,
                                  size: 20, color: scheme.error),
                              onPressed: () =>
                                  _revoquer(context, appareil['id'], isCurrent),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(Espace.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(Espace.md),
                child: Center(child: Text('Erreur: $e')),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return _buildContent(context);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Appareils de confiance')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Espace.page),
        child: _buildContent(context),
      ),
    );
  }

  void _revoquer(BuildContext context, String id, bool isCurrent) async {
    if (isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vous ne pouvez pas révoquer cet appareil')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Révoquer l\'appareil'),
        content: const Text('Voulez-vous vraiment révoquer cet appareil ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          AppButton(
            label: 'Révoquer',
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.dio.delete('$kDataDevices/$id');
        ref.invalidate(appareilsProvider);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }
}
