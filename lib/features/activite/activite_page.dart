import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/activite.dart';
import 'activite_style.dart';

export '../../core/models/activite.dart' show ActiviteEntree;

// Provider pour la liste filtrée
final activitesProvider =
    StateNotifierProvider<ActivitesNotifier, AsyncValue<List<ActiviteEntree>>>(
        (ref) {
  final apiClient = ref.read(apiClientProvider);
  return ActivitesNotifier(apiClient);
});

class ActivitesNotifier
    extends StateNotifier<AsyncValue<List<ActiviteEntree>>> {
  final ApiClient _apiClient;
  List<ActiviteEntree> _allActivities = [];
  String _typeFilter = '';
  String _userFilter = '';

  ActivitesNotifier(this._apiClient) : super(const AsyncValue.loading()) {
    chargerActivites();
  }

  void setTypeFilter(String type) {
    _typeFilter = type;
    _applyFilters();
  }

  void setUserFilter(String user) {
    _userFilter = user;
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = _allActivities;
    if (_typeFilter.isNotEmpty) {
      filtered = filtered.where((a) => a.type == _typeFilter).toList();
    }
    if (_userFilter.isNotEmpty) {
      filtered = filtered
          .where((a) => a.auteur.toLowerCase() == _userFilter.toLowerCase())
          .toList();
    }
    state = AsyncValue.data(filtered);
  }

  Future<void> chargerActivites() async {
    state = const AsyncValue.loading();
    try {
      final response = await _apiClient.dio.get(kDataActivites);
      final List<dynamic> data = response.data;
      _allActivities = data
          .map((e) => ActiviteEntree.fromJson(e as Map<String, dynamic>))
          .toList();
      _applyFilters();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

class ActivitePage extends ConsumerStatefulWidget {
  const ActivitePage({super.key});

  @override
  ConsumerState<ActivitePage> createState() => _ActivitePageState();
}

class _ActivitePageState extends ConsumerState<ActivitePage> {
  String _selectedType = '';

  void _retourSecurise(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accueil');
    }
  }

  IconData _iconForType(String type) => iconeActivite(type);

  Color _colorForType(BuildContext context, String type) =>
      couleurActivite(context, type);

  void _navigateToObject(BuildContext context, ActiviteEntree entree) {
    // La destination est portée par le modèle : le journal, le menu du badge et
    // le clic sur une notification système mènent ainsi tous les trois au même
    // endroit pour une même entrée.
    final destination = entree.destination;
    if (destination == null) return;
    context.push(destination);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activitesAsync = ref.watch(activitesProvider);
    final notifier = ref.read(activitesProvider.notifier);

    // Un filtre par type réellement émis par le serveur. La liste en comptait
    // sept sur les onze existants : dépenses, prix, comptes, paramètres et
    // sauvegardes n'étaient atteignables par aucun filtre.
    final types = kFiltresActivite.map((f) => f.$1).toList();
    final typeLabels = kFiltresActivite.map((f) => f.$2).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Journal d\'Activité'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => notifier.chargerActivites(),
              tooltip: 'Actualiser',
            ),
          ],
        ),
        body: Column(
          children: [
            // Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                Espace.page,
                Espace.sm,
                Espace.page,
                Espace.xs,
              ),
              child: Row(
                children: List.generate(types.length, (index) {
                  final t = types[index];
                  final label = typeLabels[index];
                  final isSelected = _selectedType == t;

                  return Padding(
                    padding: const EdgeInsets.only(right: Espace.xs),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedType = t);
                          notifier.setTypeFilter(t);
                        }
                      },
                      selectedColor: scheme.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: Espace.xs),

            Expanded(
              child: activitesAsync.when(
                data: (activites) {
                  if (activites.isEmpty) {
                    return const EtatVide(
                      icone: Icons.history_rounded,
                      message: 'Aucune activité enregistrée',
                      description:
                          'Les actions effectuées dans l\'application s\'afficheront chronologiquement ici.',
                    );
                  }

                  // Grouper par jour
                  final groupes = <String, List<ActiviteEntree>>{};
                  for (final a in activites) {
                    final date = DateTime.tryParse(a.date);
                    final jour = date != null
                        ? DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date)
                        : 'Date inconnue';
                    groupes.putIfAbsent(jour, () => []).add(a);
                  }
                  final jours = groupes.keys.toList();

                  return RefreshIndicator(
                    onRefresh: () async => notifier.chargerActivites(),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: Espace.xl),
                      itemCount: jours.length,
                      itemBuilder: (context, index) {
                        final jour = jours[index];
                        final entrees = groupes[jour]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Espace.page,
                                Espace.md,
                                Espace.page,
                                Espace.xs,
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.today_rounded,
                                      size: 16, color: scheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    jour.toUpperCase(),
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${entrees.length} action(s)',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...entrees.map((entree) {
                              final couleur =
                                  _colorForType(context, entree.type);
                              final bool estCliquable =
                                  entree.cibleId != null &&
                                      entree.cibleId!.isNotEmpty;

                              return AppCard(
                                onTap: estCliquable
                                    ? () => _navigateToObject(context, entree)
                                    : null,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: Espace.page,
                                  vertical: 4,
                                ),
                                padding: const EdgeInsets.all(Espace.md),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: couleur.withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(Rayon.md),
                                      ),
                                      child: Icon(
                                        _iconForType(entree.type),
                                        color: couleur,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: Espace.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entree.description,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              if (entree.auteur.isNotEmpty) ...[
                                                Icon(
                                                    Icons
                                                        .person_outline_rounded,
                                                    size: 13,
                                                    color: scheme
                                                        .onSurfaceVariant),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    entree.auteur,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              if (entree.dateTime != null) ...[
                                                Icon(Icons.access_time_rounded,
                                                    size: 13,
                                                    color: scheme
                                                        .onSurfaceVariant),
                                                const SizedBox(width: 4),
                                                Text(
                                                  DateFormat('HH:mm')
                                                      .format(entree.dateTime!),
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (entree.horsLigne)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Tooltip(
                                          message: 'Créé hors ligne',
                                          child: Icon(Icons.cloud_off_rounded,
                                              size: 16, color: scheme.outline),
                                        ),
                                      ),
                                    if (estCliquable)
                                      Icon(Icons.chevron_right_rounded,
                                          size: 18, color: scheme.outline),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Center(
                  child: Text('Erreur : $e'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
