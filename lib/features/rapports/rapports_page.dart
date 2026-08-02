import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../dashboard/dashboard_page.dart';
import '../depenses/depenses_page.dart';
import '../ventes/ventes_page.dart';
import 'rapport_modele.dart';
import 'rapport_pdf.dart';

/// Tous les mouvements de stock (réactif).
final tousMouvementsProvider = StreamProvider<List<MouvementStock>>((ref) {
  return ref.watch(storesProvider).watchMouvements();
});

// Période sélectionnée pour le rapport
final periodeRapportProvider =
    StateProvider<PlageDates>((ref) => PlageDates.mois(DateTime.now()));

// Ventes sur la période
final ventesRapportProvider = Provider<List<Vente>>((ref) {
  final pIso = ref.watch(periodeRapportProvider).periode;
  final ventes = ref.watch(toutesVentesProvider).valueOrNull ?? [];
  return ventes.where((v) => dansPeriode(v.date, pIso)).toList();
});

// Top 5 articles (par quantité vendue)
final topArticlesProvider =
    Provider<List<({String id, String nom, int quantite})>>((ref) {
  final ventes = ref.watch(ventesRapportProvider);
  final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];
  final articleMap = {for (final a in articles) a.id: a.nom};
  final Map<String, int> qteParArticle = {};
  for (final vente in ventes) {
    for (final ligne in vente.lignes) {
      qteParArticle.update(ligne.articleId, (v) => v + ligne.qte,
          ifAbsent: () => ligne.qte);
    }
  }
  final sorted = qteParArticle.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted
      .take(5)
      .map((e) =>
          (id: e.key, nom: articleMap[e.key] ?? 'Inconnu', quantite: e.value))
      .toList();
});

// Top 5 clients (par total acheté)
final topClientsProvider =
    Provider<List<({String id, String nom, int total})>>((ref) {
  final ventes = ref.watch(ventesRapportProvider);
  final clients = ref.watch(tousClientsProvider).valueOrNull ?? [];
  final clientMap = {for (final c in clients) c.id: c.nom};
  final Map<String, int> totalParClient = {};
  for (final vente in ventes) {
    totalParClient.update(vente.clientId, (v) => v + vente.totalNet,
        ifAbsent: () => vente.totalNet);
  }
  final sorted = totalParClient.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted
      .take(5)
      .map((e) => (
            id: e.key,
            nom: clientMap[e.key] ?? 'Client de passage',
            total: e.value
          ))
      .toList();
});

// Stock (valeur, alertes, mouvements)
final statsStockProvider =
    Provider<({int valeur, int alertes, int mouvements})>((ref) {
  final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];
  final valeur = articles.fold<int>(0, (sum, a) => sum + a.stock * a.prixAchat);
  final alertes = articles.where((a) => a.stock <= a.stockMin).length;
  final periode = ref.watch(periodeRapportProvider);
  final mouvements = ref.watch(tousMouvementsProvider).valueOrNull ?? [];
  final nbMouvements = mouvements.where((m) {
    final date = DateTime.tryParse(m.date);
    return date != null && periode.contient(date);
  }).length;
  return (valeur: valeur, alertes: alertes, mouvements: nbMouvements);
});

// Factures (émises sur la période, encaissé, impayé)
final statsFacturesProvider =
    Provider<({int emises, int encaisse, int impaye})>((ref) {
  final periode = ref.watch(periodeRapportProvider);
  final factures = ref.watch(toutesFacturesProvider).valueOrNull ?? [];
  final periodeFactures = factures.where((f) {
    final date = DateTime.tryParse(f.dateEmission);
    return date != null &&
        !date.isBefore(periode.debut) &&
        !date.isAfter(periode.fin);
  }).toList();
  int encaisse = 0, impaye = 0;
  for (final f in periodeFactures) {
    encaisse += montantPaye(f);
    impaye += resteDu(f);
  }
  return (emises: periodeFactures.length, encaisse: encaisse, impaye: impaye);
});

// Dépenses par nature
final depensesParNatureProvider = Provider<Map<String, int>>((ref) {
  final periode = ref.watch(periodeRapportProvider);
  final depenses = ref.watch(toutesDepensesProvider).valueOrNull ?? [];
  final map = <String, int>{};
  for (final d in depenses) {
    final date = DateTime.tryParse(d.date);
    if (date != null &&
        !date.isBefore(periode.debut) &&
        !date.isAfter(periode.fin)) {
      map.update(d.nature, (v) => v + d.montant, ifAbsent: () => d.montant);
    }
  }
  return map;
});

/// Le rapport complet de la période, tel que l'imprime l'application web.
///
/// L'écran n'affiche qu'un résumé ; le document, lui, est bâti sur les pièces
/// entières — ventes, factures, dépenses, mouvements. Il est assemblé ici, dans
/// un provider, pour que le PDF reparte exactement des mêmes données que celles
/// affichées, sans second jeu de calculs qui finirait par diverger.
final rapportCompletProvider = Provider<RapportComplet>((ref) {
  final periode = ref.watch(periodeRapportProvider);
  final utilisateur = ref.watch(utilisateurActuelProvider);
  return construireRapport(
    choix: composerPeriode(periode.debut, periode.fin),
    articles: ref.watch(tousArticlesProvider).valueOrNull ?? const [],
    ventes: ref.watch(toutesVentesProvider).valueOrNull ?? const [],
    clients: ref.watch(tousClientsProvider).valueOrNull ?? const [],
    factures: ref.watch(toutesFacturesProvider).valueOrNull ?? const [],
    depenses: ref.watch(toutesDepensesProvider).valueOrNull ?? const [],
    mouvements: ref.watch(tousMouvementsProvider).valueOrNull ?? const [],
    generePar: utilisateur?.nom ?? '',
    // Quand le compte ne voit pas les prix d'achat, la marge et la valeur
    // d'achat du stock ne sont pas calculées du tout : les masquer à l'écran
    // mais les écrire dans le PDF reviendrait à les publier.
    voitPrixAchat: utilisateur?.voitPrixAchat ?? false,
  );
});

class RapportsPage extends ConsumerStatefulWidget {
  const RapportsPage({super.key});

  @override
  ConsumerState<RapportsPage> createState() => _RapportsPageState();
}

class _RapportsPageState extends ConsumerState<RapportsPage> {
  void _retourSecurise(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accueil');
    }
  }

  void _moisPrecedent() {
    final p = ref.read(periodeRapportProvider);
    ref.read(periodeRapportProvider.notifier).state =
        PlageDates.mois(DateTime(p.debut.year, p.debut.month - 1, 1));
  }

  void _moisSuivant() {
    final p = ref.read(periodeRapportProvider);
    ref.read(periodeRapportProvider.notifier).state =
        PlageDates.mois(DateTime(p.debut.year, p.debut.month + 1, 1));
  }

  Future<void> _choisirPlage() async {
    final initial = ref.read(periodeRapportProvider);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initial.debut, end: initial.fin),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(periodeRapportProvider.notifier).state =
          PlageDates(debut: picked.start, fin: picked.end);
    }
  }

  Future<void> _exporterPdf() async {
    final rapport = ref.read(rapportCompletProvider);
    final entreprise = ref.read(entrepriseProvider).valueOrNull;
    try {
      await partagerRapportPdf(rapport, entreprise);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la génération du rapport : $e')),
      );
    }
  }

  Future<void> _imprimerPdf() async {
    final rapport = ref.read(rapportCompletProvider);
    final entreprise = ref.read(entrepriseProvider).valueOrNull;
    try {
      await imprimerRapportPdf(rapport, entreprise);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'impression : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final periode = ref.watch(periodeRapportProvider);
    final ventes = ref.watch(ventesRapportProvider);
    final topArticles = ref.watch(topArticlesProvider);
    final topClients = ref.watch(topClientsProvider);
    final stock = ref.watch(statsStockProvider);
    final factures = ref.watch(statsFacturesProvider);
    final depensesNature = ref.watch(depensesParNatureProvider);
    final caTotal = ventes.fold<int>(0, (sum, v) => sum + v.totalNet);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rapports d\'Activité'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.print_rounded),
              onPressed: _imprimerPdf,
              tooltip: 'Imprimer le rapport',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _exporterPdf,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          icon: const Icon(Icons.share_rounded),
          label: const Text('Exporter PDF',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(Espace.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carte Période du Rapport
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
                              'Plage de dates personnalisée',
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

              // Synthèse des Ventes
              const SectionHeader(
                titre: 'Synthèse des Ventes',
                icone: Icons.shopping_bag_rounded,
              ),
              const SizedBox(height: Espace.sm),

              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LigneStat(
                      label: 'Nombre de ventes conclues',
                      valeur: '${ventes.length} vente(s)',
                    ),
                    const Divider(height: 16),
                    _LigneStat(
                      label: 'Chiffre d\'affaires net',
                      valeur: fmtGNF(caTotal),
                      valeurGrasse: true,
                      couleurValeur: scheme.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.md),

              // Top 5 Articles
              if (topArticles.isNotEmpty) ...[
                Text(
                  'TOP 5 ARTICLES LES PLUS VENDUS',
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
                      for (int i = 0; i < topArticles.length; i++) ...[
                        ListTile(
                          dense: true,
                          leading: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            topArticles[i].nom,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Espace.sm,
                              vertical: Espace.xs,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(Rayon.pilule),
                            ),
                            child: Text(
                              '${topArticles[i].quantite} vendu(s)',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        if (i < topArticles.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Espace.md),
              ],

              // Top 5 Clients
              if (topClients.isNotEmpty) ...[
                Text(
                  'TOP 5 MEILLEURS CLIENTS',
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
                      for (int i = 0; i < topClients.length; i++) ...[
                        ListTile(
                          dense: true,
                          leading: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: metier.succes.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.person_rounded,
                                size: 16, color: metier.succes),
                          ),
                          title: Text(
                            topClients[i].nom,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: Text(
                            fmtGNF(topClients[i].total),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: metier.succes,
                            ),
                          ),
                        ),
                        if (i < topClients.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Espace.lg),
              ],

              // État du Stock
              const SectionHeader(
                titre: 'État du Stock',
                icone: Icons.inventory_2_rounded,
              ),
              const SizedBox(height: Espace.sm),

              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LigneStat(
                      label: 'Valeur totale du stock',
                      valeur: fmtGNF(stock.valeur),
                      valeurGrasse: true,
                    ),
                    const Divider(height: 16),
                    _LigneStat(
                      label: 'Articles en alerte de réappro.',
                      valeur: '${stock.alertes} article(s)',
                      couleurValeur:
                          stock.alertes > 0 ? scheme.error : metier.succes,
                      valeurGrasse: stock.alertes > 0,
                    ),
                    const Divider(height: 16),
                    _LigneStat(
                      label: 'Mouvements sur la période',
                      valeur: '${stock.mouvements} mouvement(s)',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.lg),

              // Activity Facturation
              const SectionHeader(
                titre: 'Facturation & Encaisses',
                icone: Icons.receipt_long_rounded,
              ),
              const SizedBox(height: Espace.sm),

              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LigneStat(
                      label: 'Factures émises',
                      valeur: '${factures.emises} facture(s)',
                    ),
                    const Divider(height: 16),
                    _LigneStat(
                      label: 'Total encaissé',
                      valeur: fmtGNF(factures.encaisse),
                      couleurValeur: metier.succes,
                      valeurGrasse: true,
                    ),
                    const Divider(height: 16),
                    _LigneStat(
                      label: 'Créances / Impayés',
                      valeur: fmtGNF(factures.impaye),
                      couleurValeur:
                          factures.impaye > 0 ? scheme.error : scheme.onSurface,
                      valeurGrasse: factures.impaye > 0,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.lg),

              // Ventilation des Dépenses
              const SectionHeader(
                titre: 'Dépenses par Nature',
                icone: Icons.payments_rounded,
              ),
              const SizedBox(height: Espace.sm),

              AppCard(
                margin: EdgeInsets.zero,
                child: depensesNature.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(Espace.sm),
                        child: Text(
                          'Aucune dépense enregistrée sur cette période.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      )
                    : Column(
                        children: [
                          for (final entry in depensesNature.entries) ...[
                            _LigneStat(
                              label: entry.key.toUpperCase(),
                              valeur: fmtGNF(entry.value),
                              valeurGrasse: true,
                            ),
                            if (entry.key != depensesNature.keys.last)
                              const Divider(height: 16),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneStat extends StatelessWidget {
  final String label;
  final String valeur;
  final bool valeurGrasse;
  final Color? couleurValeur;

  const _LigneStat({
    required this.label,
    required this.valeur,
    this.valeurGrasse = false,
    this.couleurValeur,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          valeur,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: valeurGrasse ? FontWeight.w800 : FontWeight.w600,
            color: couleurValeur ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
