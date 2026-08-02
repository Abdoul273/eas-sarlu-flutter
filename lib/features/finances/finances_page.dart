import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/finance/finance_engine.dart';
import '../dashboard/dashboard_page.dart'; // toutesVentesProvider, toutesFacturesProvider, tousArticlesProvider, utilisateurActuelProvider
import '../depenses/depenses_page.dart'; // toutesDepensesProvider

// Période sélectionnée
final periodeProvider =
    StateProvider<PlageDates>((ref) => PlageDates.mois(DateTime.now()));

// Provider du Bilan Financier complet (identique au web)
final bilanPeriodeProvider = Provider<Bilan>((ref) {
  final pIso = ref.watch(periodeProvider).periode;

  final ventes = ref.watch(toutesVentesProvider).valueOrNull ?? [];
  final factures = ref.watch(toutesFacturesProvider).valueOrNull ?? [];
  final depenses = ref.watch(toutesDepensesProvider).valueOrNull ?? [];
  final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];

  return calculerBilan(
    ventes: ventes,
    factures: factures,
    depenses: depenses,
    articles: articles,
    periode: pIso,
  );
});

// CA par jour pour le graphique
final caParJourProvider = Provider<List<BarChartGroupData>>((ref) {
  final periode = ref.watch(periodeProvider);
  final pIso = periode.periode;

  final ventes = (ref.watch(toutesVentesProvider).valueOrNull ?? [])
      .where((v) => dansPeriode(v.date, pIso))
      .toList();

  final diff = periode.fin.difference(periode.debut).inDays + 1;
  final Map<DateTime, int> caMap = {};
  for (final vente in ventes) {
    final date = DateTime.tryParse(vente.date);
    if (date != null) {
      final jour = DateTime(date.year, date.month, date.day);
      caMap.update(jour, (val) => val + vente.totalNet,
          ifAbsent: () => vente.totalNet);
    }
  }
  return List.generate(diff, (i) {
    final jour = periode.debut.add(Duration(days: i));
    final montant = caMap[jour] ?? 0;
    return BarChartGroupData(
      x: i,
      barRods: [
        BarChartRodData(
          toY: montant.toDouble(),
          color: const Color(0xFFE85D04),
          width: 10,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ],
    );
  });
});

class FinancesPage extends ConsumerStatefulWidget {
  const FinancesPage({super.key});

  @override
  ConsumerState<FinancesPage> createState() => _FinancesPageState();
}

class _FinancesPageState extends ConsumerState<FinancesPage> {
  void _retourSecurise(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accueil');
    }
  }

  void _moisPrecedent() {
    final p = ref.read(periodeProvider);
    ref.read(periodeProvider.notifier).state =
        PlageDates.mois(DateTime(p.debut.year, p.debut.month - 1, 1));
  }

  void _moisSuivant() {
    final p = ref.read(periodeProvider);
    ref.read(periodeProvider.notifier).state =
        PlageDates.mois(DateTime(p.debut.year, p.debut.month + 1, 1));
  }

  Future<void> _choisirPlage() async {
    final initial = ref.read(periodeProvider);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initial.debut, end: initial.fin),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(periodeProvider.notifier).state =
          PlageDates(debut: picked.start, fin: picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final periode = ref.watch(periodeProvider);
    final voitPrixAchat =
        ref.watch(utilisateurActuelProvider)?.voitPrixAchat ?? false;

    final bilan = ref.watch(bilanPeriodeProvider);
    final caTotal = bilan.chiffreAffaires;
    final encaissements = bilan.encaissements;
    final coutAchat = bilan.coutMarchandises;
    final charges = bilan.chargesExploitation;
    final marge = bilan.margeBrute;
    final resultatNet = bilan.resultatExploitation;
    final tresorerie = bilan.fluxTresorerie;
    final creances = bilan.creancesClients;
    final dettes = bilan.dettesFournisseurs;
    final positionNette = bilan.positionNette;
    final caParJour = ref.watch(caParJourProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finances & Analyses'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(Espace.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sélecteur de Période Card
              Container(
                padding: const EdgeInsets.all(Espace.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(Rayon.md),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: _moisPrecedent,
                        ),
                        Column(
                          children: [
                            Text(
                              DateFormat('MMMM yyyy', 'fr_FR')
                                  .format(periode.debut),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${fmtDateCourtIso(periode.debut.toIso8601String())} - ${fmtDateCourtIso(periode.fin.toIso8601String())}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: _moisSuivant,
                        ),
                      ],
                    ),
                    const SizedBox(height: Espace.xs),
                    InkWell(
                      onTap: _choisirPlage,
                      borderRadius: BorderRadius.circular(Rayon.pilule),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Espace.md,
                          vertical: Espace.xs,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(Rayon.pilule),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.date_range_rounded,
                                size: 16, color: scheme.primary),
                            const SizedBox(width: Espace.xs),
                            Text(
                              'Sélectionner une plage personnalisée',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.lg),

              // Titre Section KPI
              const SectionHeader(
                titre: 'Indicateurs Financiers',
                icone: Icons.account_balance_rounded,
              ),
              const SizedBox(height: Espace.sm),

              // Grille d'indicateurs
              if (voitPrixAchat) ...[
                Row(
                  children: [
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Chiffre d\'Affaires',
                        valeur: fmtGNF(caTotal),
                        icone: Icons.trending_up_rounded,
                        couleurIcone: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Encaissements Réels',
                        valeur: fmtGNF(encaissements),
                        icone: Icons.account_balance_wallet_rounded,
                        couleurIcone: metier.succes,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Row(
                  children: [
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Coût d\'Achat (Ventes)',
                        valeur: fmtGNF(coutAchat),
                        icone: Icons.shopping_bag_outlined,
                        couleurIcone: Colors.amber[700]!,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Marge Brute',
                        valeur: fmtGNF(marge),
                        icone: Icons.analytics_rounded,
                        couleurIcone: Colors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Row(
                  children: [
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Charges d\'Exploitation',
                        valeur: fmtGNF(charges),
                        icone: Icons.receipt_long_rounded,
                        couleurIcone: scheme.error,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Résultat Exploitation',
                        valeur: fmtGNF(resultatNet),
                        icone: Icons.pie_chart_rounded,
                        couleurIcone: resultatNet >= 0
                            ? metier.succes
                            : scheme.error,
                        destaque: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Row(
                  children: [
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Trésorerie Nette',
                        valeur: fmtGNF(tresorerie),
                        icone: Icons.savings_rounded,
                        couleurIcone:
                            tresorerie >= 0 ? scheme.primary : scheme.error,
                        destaque: true,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Position Nette',
                        valeur: fmtGNF(positionNette),
                        icone: Icons.balance_rounded,
                        couleurIcone: positionNette >= 0
                            ? metier.succes
                            : scheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Row(
                  children: [
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Créances Clients',
                        valeur: fmtGNF(creances),
                        icone: Icons.account_box_rounded,
                        couleurIcone: Colors.orange[800]!,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Dettes Fournisseurs',
                        valeur: fmtGNF(dettes),
                        icone: Icons.request_quote_rounded,
                        couleurIcone: scheme.error,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Chiffre d\'Affaires',
                        valeur: fmtGNF(caTotal),
                        icone: Icons.trending_up_rounded,
                        couleurIcone: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Encaissements Réels',
                        valeur: fmtGNF(encaissements),
                        icone: Icons.account_balance_wallet_rounded,
                        couleurIcone: metier.succes,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Row(
                  children: [
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Créances Clients',
                        valeur: fmtGNF(creances),
                        icone: Icons.account_box_rounded,
                        couleurIcone: Colors.orange[800]!,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: _IndicateurCard(
                        titre: 'Dettes Fournisseurs',
                        valeur: fmtGNF(dettes),
                        icone: Icons.request_quote_rounded,
                        couleurIcone: scheme.error,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Espace.xl),

              // Graphique CA par jour
              const SectionHeader(
                titre: 'Évolution du CA par Jour',
                icone: Icons.bar_chart_rounded,
              ),
              const SizedBox(height: Espace.sm),

              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 220,
                      child: caParJour.isEmpty
                          ? const EtatVide(
                              message: 'Aucune donnée sur la période',
                            )
                          : BarChart(
                              BarChartData(
                                barGroups: caParJour,
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: 0.5),
                                    strokeWidth: 1,
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  bottomTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false)),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 46,
                                      getTitlesWidget: (value, _) => Text(
                                        '${(value / 1000).toStringAsFixed(0)}k',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              // Répartition des charges
              if (voitPrixAchat && bilan.parCategorie.isNotEmpty) ...[
                const SizedBox(height: Espace.xl),
                const SectionHeader(
                  titre: 'Répartition des Dépenses par Catégorie',
                  icone: Icons.donut_large_rounded,
                ),
                const SizedBox(height: Espace.sm),

                AppCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 40,
                            sections: bilan.parCategorie.map((e) {
                              final color = Colors.primaries[
                                  e.categorie.hashCode %
                                      Colors.primaries.length];
                              return PieChartSectionData(
                                value: e.engage.toDouble(),
                                title: '',
                                color: color,
                                radius: 45,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: Espace.md),
                      Column(
                        children: bilan.parCategorie.map((e) {
                          final color = Colors.primaries[
                              e.categorie.hashCode % Colors.primaries.length];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: Espace.sm),
                                Expanded(
                                  child: Text(
                                    e.categorie,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  fmtGNF(e.engage),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IndicateurCard extends StatelessWidget {
  final String titre;
  final String valeur;
  final IconData icone;
  final Color couleurIcone;
  final bool destaque;

  const _IndicateurCard({
    required this.titre,
    required this.valeur,
    required this.icone,
    required this.couleurIcone,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(Espace.md),
      decoration: BoxDecoration(
        color: destaque
            ? couleurIcone.withValues(alpha: 0.08)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Rayon.md),
        border: Border.all(
          color: destaque
              ? couleurIcone.withValues(alpha: 0.3)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: couleurIcone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Rayon.sm),
                ),
                child: Icon(icone, size: 16, color: couleurIcone),
              ),
              const SizedBox(width: Espace.xs),
              Expanded(
                child: Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.xs),
          Text(
            valeur,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: destaque ? couleurIcone : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
