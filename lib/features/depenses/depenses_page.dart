import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../../core/reseau.dart';
import 'depense_form_page.dart';
import 'reglement_sheet.dart';

// Provider pour toutes les dépenses
final toutesDepensesProvider = StreamProvider<List<Depense>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchDepenses();
});

// Filtres
enum DepenseStatutFiltre { toutes, nonReglees, partielles, reglees }

final depensesFiltreesProvider = Provider.family<
    List<Depense>,
    ({
      DepenseStatutFiltre statut,
      String nature,
      DateTime? mois,
      String query,
    })>((ref, params) {
  final depensesAsync = ref.watch(toutesDepensesProvider);
  final depenses = depensesAsync.valueOrNull ?? [];
  var filtrees = depenses;

  if (params.query.isNotEmpty) {
    final q = params.query.toLowerCase();
    filtrees = filtrees
        .where((d) =>
            d.numero.toLowerCase().contains(q) ||
            d.libelle.toLowerCase().contains(q) ||
            d.beneficiaire.toLowerCase().contains(q))
        .toList();
  }

  switch (params.statut) {
    case DepenseStatutFiltre.nonReglees:
      filtrees = filtrees.where((d) => montantRegle(d) < d.montant).toList();
      break;
    case DepenseStatutFiltre.partielles:
      filtrees = filtrees.where((d) {
        final regle = montantRegle(d);
        return regle > 0 && regle < d.montant;
      }).toList();
      break;
    case DepenseStatutFiltre.reglees:
      filtrees = filtrees.where((d) => montantRegle(d) >= d.montant).toList();
      break;
    default:
      break;
  }

  if (params.nature.isNotEmpty) {
    filtrees = filtrees.where((d) => d.nature == params.nature).toList();
  }

  if (params.mois != null) {
    filtrees = filtrees.where((d) {
      try {
        final date = DateTime.parse(d.date);
        return date.year == params.mois!.year &&
            date.month == params.mois!.month;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  filtrees.sort((a, b) => b.date.compareTo(a.date));
  return filtrees;
});

// Totaux du mois courant
final totauxMoisProvider =
    Provider.family<({int total, int regle, int reste}), DateTime>((ref, mois) {
  final depenses = ref.watch(toutesDepensesProvider).valueOrNull ?? [];
  final duMois = depenses.where((d) {
    try {
      final date = DateTime.parse(d.date);
      return date.year == mois.year && date.month == mois.month;
    } catch (_) {
      return false;
    }
  }).toList();
  final total = duMois.fold<int>(0, (sum, d) => sum + d.montant);
  final regle = duMois.fold<int>(0, (sum, d) => sum + montantRegle(d));
  return (total: total, regle: regle, reste: total - regle);
});

class DepensesPage extends ConsumerStatefulWidget {
  const DepensesPage({super.key});

  @override
  ConsumerState<DepensesPage> createState() => _DepensesPageState();
}

class _DepensesPageState extends ConsumerState<DepensesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';
  String _nature = '';
  DateTime? _mois;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(
        () => setState(() => _query = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  DepenseStatutFiltre _statutFromIndex(int index) {
    switch (index) {
      case 0:
        return DepenseStatutFiltre.toutes;
      case 1:
        return DepenseStatutFiltre.nonReglees;
      case 2:
        return DepenseStatutFiltre.partielles;
      case 3:
        return DepenseStatutFiltre.reglees;
      default:
        return DepenseStatutFiltre.toutes;
    }
  }

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
    final moisActuel = _mois ?? DateTime.now();
    final totaux = ref.watch(totauxMoisProvider(moisActuel));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dépenses & Charges'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _nouvelleDepense(context),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouvelle Dépense',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Column(
          children: [
            // KPI Summary Header Card
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espace.page,
                Espace.sm,
                Espace.page,
                Espace.xs,
              ),
              child: Container(
                padding: const EdgeInsets.all(Espace.md),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.surfaceContainerHighest,
                      scheme.surfaceContainerLow,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Rayon.md),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_month_rounded,
                                size: 18, color: scheme.primary),
                            const SizedBox(width: Espace.xs),
                            Text(
                              DateFormat('MMMM yyyy', 'fr_FR').format(moisActuel),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _choisirMois,
                          borderRadius: BorderRadius.circular(Rayon.pilule),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Espace.sm + 2,
                              vertical: Espace.xs,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(Rayon.pilule),
                            ),
                            child: Text(
                              'Changer de mois',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Espace.md),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total engagé',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fmtGNF(totaux.total),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: scheme.outlineVariant,
                        ),
                        const SizedBox(width: Espace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Réglé',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fmtGNF(totaux.regle),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: context.metier.succes,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: scheme.outlineVariant,
                        ),
                        const SizedBox(width: Espace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reste à régler',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fmtGNF(totaux.reste),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: totaux.reste > 0
                                      ? scheme.error
                                      : scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Barre de recherche
            AppSearchBar(
              controller: _searchController,
              hintText: 'Rechercher par n°, libellé ou bénéficiaire…',
            ),

            // Chips de filtrage par nature
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Espace.page),
              child: Row(
                children: [
                  _ChipNature(
                    label: 'Toutes les natures',
                    selectionne: _nature == '',
                    onSelected: () => setState(() => _nature = ''),
                  ),
                  const SizedBox(width: Espace.xs),
                  _ChipNature(
                    label: 'Marchandise',
                    selectionne: _nature == 'marchandise',
                    onSelected: () => setState(() => _nature = 'marchandise'),
                  ),
                  const SizedBox(width: Espace.xs),
                  _ChipNature(
                    label: 'Exploitation',
                    selectionne: _nature == 'exploitation',
                    onSelected: () => setState(() => _nature = 'exploitation'),
                  ),
                  const SizedBox(width: Espace.xs),
                  _ChipNature(
                    label: 'Investissement',
                    selectionne: _nature == 'investissement',
                    onSelected: () =>
                        setState(() => _nature = 'investissement'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.xs),

            // TabBar de statut
            TabBar(
              controller: _tabController,
              labelColor: scheme.primary,
              indicatorColor: scheme.primary,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Toutes'),
                Tab(text: 'Non réglées'),
                Tab(text: 'Partielles'),
                Tab(text: 'Réglées'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: List.generate(4, (index) {
                  final statut = _statutFromIndex(index);
                  final params = (
                    statut: statut,
                    nature: _nature,
                    mois: _mois,
                    query: _query
                  );
                  final depenses = ref.watch(depensesFiltreesProvider(params));
                  return depenses.isEmpty
                      ? const EtatVide(
                          icone: Icons.payments_outlined,
                          message: 'Aucune dépense enregistrée',
                          description:
                              'Les dépenses correspondant à vos filtres s\'afficheront ici.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: depenses.length,
                          itemBuilder: (context, i) => _DepenseCard(
                            depense: depenses[i],
                            onTap: () => _afficherDetail(context, depenses[i]),
                          ),
                        );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _choisirMois() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _mois ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) {
      setState(() => _mois = DateTime(date.year, date.month));
    }
  }

  void _nouvelleDepense(BuildContext context) {
    context.pushNamed('nouvelle-depense');
  }

  void _afficherDetail(BuildContext context, Depense depense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _DepenseDetailSheet(depense: depense),
    );
  }
}

class _ChipNature extends StatelessWidget {
  final String label;
  final bool selectionne;
  final VoidCallback onSelected;

  const _ChipNature({
    required this.label,
    required this.selectionne,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selectionne,
      onSelected: (_) => onSelected(),
      selectedColor: scheme.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selectionne ? scheme.primary : scheme.onSurfaceVariant,
        fontWeight: selectionne ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DepenseCard extends StatelessWidget {
  final Depense depense;
  final VoidCallback onTap;

  const _DepenseCard({required this.depense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final regle = montantRegle(depense);
    final reste = depense.montant - regle;

    late final String statut;
    late final Color statutColor;
    if (regle >= depense.montant) {
      statut = 'Réglée';
      statutColor = metier.succes;
    } else if (regle > 0) {
      statut = 'Partielle';
      statutColor = metier.alerte;
    } else {
      statut = 'Non réglée';
      statutColor = scheme.error;
    }

    late final Color natureColor;
    switch (depense.nature) {
      case 'marchandise':
        natureColor = Colors.blue;
        break;
      case 'exploitation':
        natureColor = Colors.teal;
        break;
      default:
        natureColor = Colors.purple;
        break;
    }

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Espace.sm,
                  vertical: Espace.xs,
                ),
                decoration: BoxDecoration(
                  color: natureColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Rayon.sm),
                ),
                child: Text(
                  depense.nature.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: natureColor,
                  ),
                ),
              ),
              const SizedBox(width: Espace.xs),
              Text(
                depense.numero.isNotEmpty ? depense.numero : '…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              BadgePastille(texte: statut, couleur: statutColor),
            ],
          ),
          const SizedBox(height: Espace.sm),
          Text(
            depense.libelle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (depense.beneficiaire.isNotEmpty)
            Text(
              'Bénéficiaire : ${depense.beneficiaire}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: Espace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fmtDateCourtIso(depense.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtGNF(depense.montant),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                  if (reste > 0)
                    Text(
                      'Reste : ${fmtGNF(reste)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Feuille de détail modernisée (style VenteDetailSheet)
class _DepenseDetailSheet extends ConsumerWidget {
  final Depense depense;
  const _DepenseDetailSheet({required this.depense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final regle = montantRegle(depense);
    final reste = depense.montant - regle;
    final ratioRegle =
        depense.montant > 0 ? (regle / depense.montant).clamp(0.0, 1.0) : 0.0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: Rayon.feuille,
          ),
          child: Column(
            children: [
              const PoigneeFeuille(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    Espace.page,
                    Espace.xs,
                    Espace.page,
                    Espace.md,
                  ),
                  children: [
                    // Header Banner Card
                    Container(
                      padding: const EdgeInsets.all(Espace.md),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(Rayon.md),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(Rayon.md),
                            ),
                            child: Icon(Icons.payments_rounded,
                                color: scheme.primary, size: 26),
                          ),
                          const SizedBox(width: Espace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  depense.numero.isNotEmpty
                                      ? depense.numero
                                      : 'Dépense',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Engagée le ${fmtDateIso(depense.date)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DepenseFormPage(depense: depense),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded,
                                color: scheme.error),
                            onPressed: () =>
                                _supprimerDepense(context, ref, depense),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Espace.md),

                    // Synthèse financière & Barre de progression
                    AppCard(
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Montant Total',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                fmtGNF(depense.montant),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Espace.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(Rayon.pilule),
                            child: LinearProgressIndicator(
                              value: ratioRegle,
                              minHeight: 8,
                              backgroundColor: scheme.surfaceContainerHighest,
                              color: ratioRegle >= 1.0
                                  ? metier.succes
                                  : scheme.primary,
                            ),
                          ),
                          const SizedBox(height: Espace.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  'Réglé : ${fmtGNF(regle)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: metier.succes,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Espace.sm),
                              Flexible(
                                child: Text(
                                  'Reste : ${fmtGNF(reste)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: reste > 0
                                        ? scheme.error
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Espace.md),

                    // Informations détaillées
                    AppCard(
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INFORMATIONS DE LA DÉPENSE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: Espace.sm),
                          _LigneInfo(
                              libelle: 'Libellé', valeur: depense.libelle),
                          _LigneInfo(
                              libelle: 'Nature',
                              valeur: depense.nature.toUpperCase()),
                          if (depense.categorie.isNotEmpty)
                            _LigneInfo(
                                libelle: 'Catégorie',
                                valeur: depense.categorie),
                          if (depense.beneficiaire.isNotEmpty)
                            _LigneInfo(
                                libelle: 'Bénéficiaire',
                                valeur: depense.beneficiaire),
                          if (depense.reference.isNotEmpty)
                            _LigneInfo(
                                libelle: 'Référence',
                                valeur: depense.reference),
                          if (depense.note.isNotEmpty)
                            _LigneInfo(libelle: 'Note', valeur: depense.note),
                        ],
                      ),
                    ),
                    const SizedBox(height: Espace.md),

                    // Actions & Règlements
                    if (reste > 0) ...[
                      AppButton(
                        label: 'Ajouter un règlement',
                        icon: Icons.add_card_rounded,
                        onPressed: () => _ajouterReglement(context, depense),
                        expanded: true,
                      ),
                      const SizedBox(height: Espace.md),
                    ],

                    Text(
                      'HISTORIQUE DES RÈGLEMENTS (${depense.reglements.length})',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: Espace.xs),

                    AppCard(
                      margin: EdgeInsets.zero,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          if (depense.reglements.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(Espace.md),
                              child: Text(
                                'Aucun règlement enregistré pour cette dépense.',
                                style: TextStyle(fontStyle: FontStyle.italic),
                              ),
                            )
                          else
                            for (int i = 0;
                                i < depense.reglements.length;
                                i++) ...[
                              ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        metier.succes.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(Rayon.sm),
                                  ),
                                  child: Icon(Icons.check_circle_rounded,
                                      color: metier.succes, size: 18),
                                ),
                                title: Text(
                                  fmtGNF(depense.reglements[i].montant),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${depense.reglements[i].mode} • le ${fmtDateCourtIso(depense.reglements[i].date)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline_rounded,
                                      size: 20, color: scheme.error),
                                  onPressed: () => _supprimerReglement(
                                      context, ref, depense, depense.reglements[i]),
                                ),
                              ),
                              if (i < depense.reglements.length - 1)
                                const Divider(height: 1),
                            ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _ajouterReglement(BuildContext context, Depense depense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ReglementSheet(depense: depense),
    );
  }

  void _supprimerReglement(BuildContext context, WidgetRef ref, Depense depense,
      Reglement reglement) async {
    if (!await aUneConnexion()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connexion requise pour supprimer un règlement')));
      return;
    }
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le règlement'),
        content: Text(
            'Supprimer ${fmtGNF(reglement.montant)} du ${fmtDateIso(reglement.date)} ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          AppButton(
              label: 'Supprimer',
              isDestructive: true,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.dio.delete(
            '$kDataDepenseReglementDelete${depense.id}/${reglement.id}');
        final stores = ref.read(storesProvider);
        await stores.upsert(
            'depense',
            depense.copyWith(
                reglements: depense.reglements
                    .where((r) => r.id != reglement.id)
                    .toList()));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  void _supprimerDepense(
      BuildContext context, WidgetRef ref, Depense depense) async {
    if (!await aUneConnexion()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connexion requise pour supprimer une dépense')));
      return;
    }
    if (!context.mounted) return;
    // Une dépense sur laquelle de l'argent est déjà sorti ne s'efface pas :
    // le règlement disparaîtrait de la trésorerie sans que la caisse, elle,
    // ne le retrouve.
    final regle = montantRegle(depense);
    if (regle > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${fmtGNF(regle)} ont déjà été réglés sur cette dépense : '
            'elle ne peut plus être supprimée.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la dépense'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          AppButton(
              label: 'Supprimer',
              isDestructive: true,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.dio.delete('$kDataDepenseDelete${depense.id}');
        final stores = ref.read(storesProvider);
        await stores.supprimerDepense(depense.id);
        if (!context.mounted) return;
        Navigator.pop(context);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }
}

class _LigneInfo extends StatelessWidget {
  final String libelle;
  final String valeur;

  const _LigneInfo({required this.libelle, required this.valeur});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            libelle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            valeur,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
