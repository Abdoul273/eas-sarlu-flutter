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

/// Ce que l'activité a fait entrer net dans la caisse depuis l'origine.
/// Volontairement HORS période : c'est un cumul, et le tableau de bord affiche
/// exactement le même chiffre.
final enCaissseFinancesProvider = Provider<int>((ref) {
  return tresorerieNette(
    factures: ref.watch(toutesFacturesProvider).valueOrNull ?? const [],
    depenses: ref.watch(toutesDepensesProvider).valueOrNull ?? const [],
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
    final periode = ref.watch(periodeProvider);
    final voitPrixAchat =
        ref.watch(utilisateurActuelProvider)?.voitPrixAchat ?? false;

    final bilan = ref.watch(bilanPeriodeProvider);
    // Le prix d'achat est figé sur chaque ligne depuis septembre 2026 ; les
    // ventes plus anciennes sont estimées au prix courant, et on le dit
    // seulement quand il y en a dans la période.
    final estime = (ref.watch(toutesVentesProvider).valueOrNull ?? const [])
        .where((v) => dansPeriode(v.date, periode.periode))
        .any(venteAuCoutEstime);
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
    final decaissements = bilan.decaissements;
    final achatsMarchandises = bilan.achatsMarchandises;
    final investissements = bilan.investissements;
    // Depuis l'origine, et non sur la période : c'est le même chiffre que
    // « En caisse » sur le tableau de bord, calculé par le même moteur.
    final enCaisse = ref.watch(enCaissseFinancesProvider);
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

              // ══ 1. LE RÉSULTAT ══════════════════════════════════════════
              // Lu comme un compte de résultat, de haut en bas, chaque ligne
              // découlant de la précédente. La grille de tuiles qu'il y avait
              // ici posait le chiffre d'affaires à côté de la trésorerie sans
              // rien dire de leur rapport — or ces deux chiffres ne répondent
              // pas à la même question, et les additionner n'a aucun sens.
              if (voitPrixAchat) ...[
                const SectionHeader(
                  titre: 'Résultat de la période',
                  icone: Icons.assessment_rounded,
                ),
                const SizedBox(height: Espace.xs),
                Text(
                  'Ce que le commerce gagne, indépendamment de qui a payé quand.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Espace.sm),
                AppCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _LigneCompte(
                        libelle: "Chiffre d'affaires",
                        detail: '${bilan.nbVentes} vente'
                            '${bilan.nbVentes > 1 ? 's' : ''}',
                        montant: caTotal,
                      ),
                      _LigneCompte(
                        libelle: 'Coût des marchandises vendues',
                        detail: estime
                            ? "en partie estimé au prix d'achat actuel"
                            : "au prix d'achat du jour de chaque vente",
                        montant: -coutAchat,
                      ),
                      const Divider(height: Espace.lg),
                      _LigneCompte(
                        libelle: 'Marge brute',
                        detail: bilan.tauxMarge == null
                            ? 'aucune vente'
                            : '${bilan.tauxMarge!.toStringAsFixed(1)} % du CA',
                        montant: marge,
                        sousTotal: true,
                      ),
                      _LigneCompte(
                        libelle: "Charges d'exploitation",
                        detail: 'loyer, salaires, transport, carburant…',
                        montant: -charges,
                      ),
                      const Divider(height: Espace.lg),
                      _LigneCompte(
                        libelle: "Résultat d'exploitation",
                        detail: resultatNet >= 0 ? 'bénéfice' : 'perte',
                        montant: resultatNet,
                        total: true,
                      ),
                    ],
                  ),
                ),
                if (estime) ...[
                  const SizedBox(height: Espace.xs),
                  const _NoteExplicative(
                    'Certaines ventes de la période sont antérieures à la '
                    'mémorisation du prix d\'achat : leur coût est estimé au '
                    'prix d\'achat ACTUEL de l\'article. Les ventes récentes '
                    'portent le prix du jour où elles ont été faites.',
                  ),
                ],
                const SizedBox(height: Espace.xl),
              ],

              // ══ 2. LA TRÉSORERIE ════════════════════════════════════════
              const SectionHeader(
                titre: 'Trésorerie de la période',
                icone: Icons.account_balance_wallet_rounded,
              ),
              const SizedBox(height: Espace.xs),
              Text(
                'Ce qui est réellement passé par la caisse. À ne jamais '
                'additionner avec le résultat : ce sont deux lectures du même '
                'mois.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LigneCompte(
                      libelle: 'Encaissements clients',
                      detail: 'versements reçus sur factures',
                      montant: encaissements,
                    ),
                    _LigneCompte(
                      libelle: 'Décaissements',
                      detail: 'règlements versés, toutes natures',
                      montant: -decaissements,
                    ),
                    const Divider(height: Espace.lg),
                    _LigneCompte(
                      libelle: 'Flux net de la période',
                      detail: tresorerie >= 0
                          ? 'la caisse a monté'
                          : 'la caisse a baissé',
                      montant: tresorerie,
                      total: true,
                    ),
                  ],
                ),
              ),

              // Ce que le gérant cherche quand il demande « où sont passés mes
              // millions ? ». Ces sorties ne figurent PAS au résultat, et leur
              // absence de l'écran faisait croire à un oubli de l'application.
              if (voitPrixAchat &&
                  (achatsMarchandises > 0 || investissements > 0)) ...[
                const SizedBox(height: Espace.sm),
                AppCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sorties de caisse hors résultat',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Engagé sur la période. Ce n\'est pas de l\'argent '
                        'perdu : c\'est de la marchandise en dépôt et du '
                        'matériel qui durera.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Espace.sm),
                      if (achatsMarchandises > 0)
                        _LigneCompte(
                          libelle: 'Achats de marchandise',
                          detail: 'entrera au résultat à la revente',
                          montant: -achatsMarchandises,
                          couleur: Color(couleurNature['marchandise']!),
                        ),
                      if (investissements > 0)
                        _LigneCompte(
                          libelle: 'Investissements',
                          detail: 'biens durables : véhicule, outillage, travaux',
                          montant: -investissements,
                          couleur: Color(couleurNature['investissement']!),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                child: _LigneCompte(
                  libelle: "En caisse depuis l'origine",
                  detail: 'cumul encaissé − décaissé, pas un solde de coffre',
                  montant: enCaisse,
                  total: true,
                ),
              ),
              const SizedBox(height: Espace.xl),

              // ══ 3. CE QUI RESTE DEHORS ══════════════════════════════════
              const SectionHeader(
                titre: 'Position à la fin de la période',
                icone: Icons.balance_rounded,
              ),
              const SizedBox(height: Espace.xs),
              Text(
                'L\'argent promis de part et d\'autre, qui n\'a pas encore '
                'bougé.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LigneCompte(
                      libelle: 'Créances clients',
                      detail: 'ce qu\'ils nous doivent',
                      montant: creances,
                    ),
                    _LigneCompte(
                      libelle: 'Dettes fournisseurs',
                      detail: 'ce que nous devons',
                      montant: -dettes,
                    ),
                    const Divider(height: Espace.lg),
                    _LigneCompte(
                      libelle: 'Position nette',
                      detail: positionNette >= 0
                          ? 'on nous doit plus qu\'on ne doit'
                          : 'on doit plus qu\'on ne nous doit',
                      montant: positionNette,
                      total: true,
                    ),
                  ],
                ),
              ),
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

class _LigneCompte extends StatelessWidget {
  const _LigneCompte({
    required this.libelle,
    required this.montant,
    this.detail,
    this.sousTotal = false,
    this.total = false,
    this.couleur,
  });

  final String libelle;

  /// Négatif pour ce qui se retranche. Le signe porte le sens : un coût affiché
  /// en positif au milieu d'une soustraction se relit toujours de travers.
  final int montant;
  final String? detail;
  final bool sousTotal;
  final bool total;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final teinte = couleur ??
        (total
            ? (montant >= 0 ? metier.succes : metier.danger)
            : (montant < 0 ? scheme.onSurfaceVariant : scheme.onSurface));

    final style = total
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)
        : sousTotal
            ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
            : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(libelle, style: style),
                if (detail != null)
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Espace.sm),
          Text(
            // Le signe « moins » typographique, et la valeur absolue : « − 6 M »
            // se lit d'un coup d'œil là où « -6 000 000 » se déchiffre.
            '${montant < 0 ? '− ' : ''}${fmtGNF(montant.abs())}',
            style: style?.copyWith(
              color: teinte,
              fontWeight: total
                  ? FontWeight.w900
                  : (sousTotal ? FontWeight.w700 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une précision que le chiffre ne peut pas porter tout seul.
class _NoteExplicative extends StatelessWidget {
  const _NoteExplicative(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded,
            size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: Espace.xs),
        Expanded(
          child: Text(
            texte,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
          ),
        ),
      ],
    );
  }
}
