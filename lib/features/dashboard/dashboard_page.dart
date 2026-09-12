import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../../core/auth/auth_state.dart';
import '../../core/db/stores.dart';


import '../ventes/ventes_page.dart' show clientMapProvider;
import '../depenses/depenses_page.dart' show toutesDepensesProvider;
import 'package:go_router/go_router.dart';

import '../../app/router.dart' show ouvrirRoute;

/// Abrège un montant pour l'axe du graphique : « 1,2 M » plutôt que
/// « 1 200 000 », qui ne tient pas dans la marge réservée.
String _abregerMontant(double valeur) {
  if (valeur >= 1000000) {
    final m = valeur / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1).replaceAll('.', ',')} M';
  }
  if (valeur >= 1000) return '${(valeur / 1000).round()} k';
  return valeur.round().toString();
}

// --- Providers dédiés au tableau de bord ---

/// Utilisateur connecté
final utilisateurActuelProvider = Provider<Utilisateur?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value?.user;
});

/// Liste de toutes les ventes (réactive)
final toutesVentesProvider = StreamProvider<List<Vente>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchVentes();
});

/// Liste de toutes les factures
final toutesFacturesProvider = StreamProvider<List<Facture>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchFactures();
});



/// Liste des articles
final tousArticlesProvider = StreamProvider<List<Article>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchArticles();
});

/// Les comptes du magasin, tels que le dernier instantané les a laissés.
///
/// Le serveur ne détaille les droits des AUTRES comptes qu'à qui détient le
/// droit « utilisateurs » : ce qui arrive ici est déjà filtré à la source, et
/// afficher cette liste n'ouvre donc rien qui soit fermé ailleurs.
final tousUtilisateursProvider = StreamProvider<List<Utilisateur>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchUtilisateurs();
});

/// Mode confidentialité : masque les montants par défaut
final masquerMontantsProvider = StateProvider<bool>((ref) => true);

String _fmtMontantDashboard(int montant, bool masque) {
  return masque ? '•••• GNF' : fmtGNF(montant);
}

// --- Données calculées ---

/// Ventes du jour (montant total et nombre)
final ventesDuJourProvider = Provider<({int nombre, int montant})>((ref) {
  final ventes = ref.watch(toutesVentesProvider).valueOrNull ?? [];
  final pJour = Periode.jour(DateTime.now());
  final ventesJour = ventes.where((v) => dansPeriode(v.date, pJour)).toList();
  final total = ventesJour.fold<int>(0, (sum, v) => sum + v.totalNet);
  return (nombre: ventesJour.length, montant: total);
});

/// Encaissements du jour (somme des paiements reçus aujourd'hui)
final encaissementsDuJourProvider = Provider<int>((ref) {
  final factures = ref.watch(toutesFacturesProvider).valueOrNull ?? [];
  final pJour = Periode.jour(DateTime.now());
  int total = 0;
  for (final facture in factures) {
    for (final paiement in facture.paiements) {
      if (dansPeriode(paiement.date, pJour)) {
        total += paiement.montant;
      }
    }
  }
  return total;
});

/// Valeur totale du stock (coût d'achat)
final valeurStockProvider = Provider<int>((ref) {
  final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];
  return valeurStockAchat(articles);
});

/// Ce que l'activité a fait entrer net dans la caisse depuis l'origine.
///
/// L'addition elle-même est dans `finance_engine.dart`, avec toutes les autres :
/// écrite ici, elle aurait fini par dire autre chose que la page Finances, qui
/// calcule le même flux de trésorerie par le bilan.
final tresorerieNetteProvider = Provider<int>((ref) {
  return tresorerieNette(
    factures: ref.watch(toutesFacturesProvider).valueOrNull ?? const [],
    depenses: ref.watch(toutesDepensesProvider).valueOrNull ?? const [],
  );
});

/// Factures impayées (nombre et total restant dû)
final facturesImpayeesProvider =
    Provider<({int nombre, int resteTotal})>((ref) {
  final factures = ref.watch(toutesFacturesProvider).valueOrNull ?? [];
  final impayees = factures.where((f) => resteDu(f) > 0).toList();
  final resteTotal = impayees.fold<int>(0, (sum, f) => sum + resteDu(f));
  return (nombre: impayees.length, resteTotal: resteTotal);
});

/// Articles en alerte : rupture ou stock faible, selon `stockStatut`.
final articlesAlerteProvider = Provider<List<Article>>((ref) {
  final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];
  return articles.where(stockEnAlerte).toList();
});

/// 5 dernières ventes
final dernieresVentesProvider = Provider<List<Vente>>((ref) {
  final ventes = ref.watch(toutesVentesProvider).valueOrNull ?? [];
  final triees = List<Vente>.from(ventes)
    ..sort((a, b) => b.date.compareTo(a.date));
  return triees.take(5).toList();
});

/// Données pour le graphique des 7 derniers jours
final ventes7JoursProvider = Provider<List<BarChartGroupData>>((ref) {
  final ventes = ref.watch(toutesVentesProvider).valueOrNull ?? [];
  final maintenant = DateTime.now();
  final jours = List.generate(7, (i) {
    final date = maintenant.subtract(Duration(days: 6 - i));
    return DateFormat('yyyy-MM-dd').format(date);
  });

  final ventesParJour = <String, int>{};
  for (final v in ventes) {
    try {
      final dateVente = DateTime.parse(v.date);
      final cle = DateFormat('yyyy-MM-dd').format(dateVente);
      ventesParJour.update(cle, (val) => val + v.totalNet,
          ifAbsent: () => v.totalNet);
    } catch (_) {}
  }

  return List.generate(7, (i) {
    final jour = jours[i];
    final montant = ventesParJour[jour] ?? 0;
    return BarChartGroupData(x: i, barRods: [
      BarChartRodData(
        toY: montant.toDouble(),
        width: 15,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        gradient: const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFFF48C06), kCouleurMarque],
        ),
      )
    ]);
  });
});

// --- Page principale ---

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  // Le bouton flottant est désormais déduit de la route par AppShell : le faire
  // pousser ici par la page obligeait à toucher un provider depuis dispose(),
  // ce que Riverpod interdit (« Cannot use ref after the widget was disposed »).

  @override
  Widget build(BuildContext context) {
    final utilisateur = ref.watch(utilisateurActuelProvider);
    final voitPrixAchat = utilisateur?.voitPrixAchat ?? false;
    final masque = ref.watch(masquerMontantsProvider);
    final maintenant = DateTime.now();
    final dateDuJour = fmtDate(maintenant);
    final prenom = utilisateur?.nom.split(' ').first ?? 'Vendeur';

    return SingleChildScrollView(
      // `basDeListe` : la barre de navigation et le bouton flottant recouvrent
      // le bas de l'écran — sans cette réserve le graphique passe dessous.
      padding: const EdgeInsets.only(top: Espace.sm, bottom: Espace.basDeListe),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête Hero Gradient
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espace.page),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Espace.lg + 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Rayon.xl),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Color.lerp(Theme.of(context).colorScheme.primary, const Color(0xFFE85D04), 0.5)!,
                    const Color(0xFFC23E00),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bonjour $prenom 👋',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateDuJour,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: masque ? 'Afficher les montants' : 'Masquer les montants',
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          onPressed: () {
                            ref.read(masquerMontantsProvider.notifier).state = !masque;
                          },
                          icon: Icon(
                            masque ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espace.lg),
                  // Raccourcis d'actions rapides
                  Row(
                    children: [
                      Expanded(
                        child: _RaccourciAction(
                          label: 'Vendre',
                          icone: Icons.add_shopping_cart_rounded,
                          onTap: () => context.pushNamed('nouvelle-vente'),
                        ),
                      ),
                      const SizedBox(width: Espace.sm),
                      Expanded(
                        child: _RaccourciAction(
                          label: 'Stock',
                          icone: Icons.inventory_2_rounded,
                          onTap: () => context.goNamed('stock'),
                        ),
                      ),
                      const SizedBox(width: Espace.sm),
                      Expanded(
                        child: _RaccourciAction(
                          label: 'Factures',
                          icone: Icons.receipt_long_rounded,
                          onTap: () => context.goNamed('factures'),
                        ),
                      ),
                      const SizedBox(width: Espace.sm),
                      Expanded(
                        child: _RaccourciAction(
                          label: 'Clients',
                          icone: Icons.people_alt_rounded,
                          onTap: () => context.goNamed('clients'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Espace.xl),

          // Bande de tuiles statistiques, défilable horizontalement.
          SizedBox(
            height: kHauteurStatTile,
            child: ListView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(
                  horizontal: Espace.page - Espace.xs - 2),
              children: [
                _buildStatVentesJour(),
                _buildStatEncaissements(),
                if (voitPrixAchat) _buildStatValeurStock(),
                _buildStatFacturesImpayees(),
                if (voitPrixAchat) _buildStatTresorerie(),
              ],
            ),
          ),
          const SizedBox(height: Espace.lg),

          _buildAlertesStock(),
          const SizedBox(height: Espace.sm),

          _buildDernieresVentes(),
          const SizedBox(height: Espace.sm),

          _buildGraphique7Jours(),
        ],
      ),
    );
  }

  // Les tuiles n'insèrent jamais de « \n » dans la valeur : la seconde ligne
  // passe par `sousTitre`, qui est mesuré par la tuile.

  Widget _buildStatVentesJour() {
    final data = ref.watch(ventesDuJourProvider);
    final masque = ref.watch(masquerMontantsProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: kLargeurStatTile),
      child: StatTile(
        libelle: 'Ventes du jour',
        valeur: _fmtMontantDashboard(data.montant, masque),
        sousTitre: '${data.nombre} vente(s)',
        icone: Icons.point_of_sale_rounded,
        couleurValeur: Theme.of(context).colorScheme.primary,
        onTap: () => context.goNamed('ventes'),
      ),
    );
  }

  Widget _buildStatEncaissements() {
    final total = ref.watch(encaissementsDuJourProvider);
    final masque = ref.watch(masquerMontantsProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: kLargeurStatTile),
      child: StatTile(
        libelle: 'Encaissements',
        valeur: _fmtMontantDashboard(total, masque),
        sousTitre: 'Reçus aujourd\'hui',
        icone: Icons.payments_rounded,
        couleurValeur: context.metier.succes,
      ),
    );
  }

  Widget _buildStatValeurStock() {
    final valeur = ref.watch(valeurStockProvider);
    final masque = ref.watch(masquerMontantsProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: kLargeurStatTile),
      child: StatTile(
        libelle: 'Valeur stock',
        valeur: _fmtMontantDashboard(valeur, masque),
        sousTitre: 'Au prix d\'achat',
        icone: Icons.warehouse_rounded,
        couleurValeur: context.metier.info,
        onTap: () => context.goNamed('stock'),
      ),
    );
  }

  Widget _buildStatTresorerie() {
    final valeur = ref.watch(tresorerieNetteProvider);
    final masque = ref.watch(masquerMontantsProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: kLargeurStatTile),
      child: StatTile(
        libelle: 'En caisse',
        valeur: _fmtMontantDashboard(valeur, masque),
        // Le sous-titre répétait le libellé. Il dit maintenant CE QUE le
        // chiffre recouvre : un cumul de mouvements, pas le contenu du coffre —
        // ni le fonds de caisse d'origine ni les prélèvements du gérant n'étant
        // enregistrés nulle part.
        sousTitre: 'Encaissé − décaissé',
        icone: Icons.account_balance_wallet_rounded,
        couleurValeur: valeur < 0
            ? context.metier.danger
            : context.metier.succes,
        onTap: () => ouvrirRoute(context, 'finances'),
      ),
    );
  }

  Widget _buildStatFacturesImpayees() {
    final data = ref.watch(facturesImpayeesProvider);
    final masque = ref.watch(masquerMontantsProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: kLargeurStatTile),
      child: StatTile(
        libelle: 'Impayés',
        valeur: _fmtMontantDashboard(data.resteTotal, masque),
        sousTitre: '${data.nombre} facture(s)',
        icone: Icons.receipt_long_rounded,
        couleurValeur: context.metier.danger,
        onTap: () => context.goNamed('factures'),
      ),
    );
  }

  Widget _buildAlertesStock() {
    final articles = ref.watch(articlesAlerteProvider);
    final alerte = context.metier.alerte;
    // Au-delà de 4 lignes la carte s'étire sans fin : on tronque et on renvoie
    // vers la page Stock pour le reste.
    final visibles = articles.take(4).toList();
    final reste = articles.length - visibles.length;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
          Espace.lg, Espace.md, Espace.md, Espace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            titre: 'Alertes stock',
            icone: Icons.warning_amber_rounded,
            couleurIcone: alerte,
            actionLabel: articles.isEmpty ? null : 'Voir tout',
            onAction: articles.isEmpty ? null : () => context.goNamed('stock'),
          ),
          const SizedBox(height: Espace.xs),
          if (articles.isEmpty)
            const EtatVide(
              message: 'Aucun article en alerte',
              description: 'Tous les niveaux sont au-dessus du minimum.',
              icone: Icons.check_circle_outline_rounded,
              compact: true,
            )
          else ...[
            for (final article in visibles)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Espace.xs),
                visualDensity: VisualDensity.compact,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: alerte.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(Rayon.sm),
                  ),
                  child: Icon(Icons.inventory_2_rounded, size: 18, color: alerte),
                ),
                title: Text(
                  article.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Stock ${article.stock} ${article.unite} • min ${article.stockMin}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => context.pushNamed('detail-article',
                    pathParameters: {'id': article.id}),
              ),
            if (reste > 0)
              Padding(
                padding: const EdgeInsets.only(left: Espace.xs, top: Espace.xs),
                child: Text(
                  '+ $reste autre(s) article(s) en alerte',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDernieresVentes() {
    final ventes = ref.watch(dernieresVentesProvider);
    final clients = ref.watch(clientMapProvider);
    final masque = ref.watch(masquerMontantsProvider);
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
          Espace.lg, Espace.md, Espace.md, Espace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            titre: 'Dernières ventes',
            icone: Icons.receipt_rounded,
            actionLabel: ventes.isEmpty ? null : 'Voir tout',
            onAction: ventes.isEmpty ? null : () => context.goNamed('ventes'),
          ),
          const SizedBox(height: Espace.xs),
          if (ventes.isEmpty)
            const EtatVide(
              message: 'Aucune vente enregistrée',
              description: 'La première vente apparaîtra ici.',
              icone: Icons.point_of_sale_outlined,
              compact: true,
            )
          else
            for (final vente in ventes)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Espace.xs),
                visualDensity: VisualDensity.compact,
                title: Text(
                  vente.numero.isEmpty ? 'En attente…' : vente.numero,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  clients[vente.clientId]?.nom ?? 'Client de passage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Colonne à largeur bornée : un montant long poussait sinon le
                // titre hors de la tuile.
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _fmtMontantDashboard(vente.totalNet, masque),
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      if (vente.date.isNotEmpty)
                        Text(
                          fmtHeureIso(vente.date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildGraphique7Jours() {
    final barGroups = ref.watch(ventes7JoursProvider);
    final maintenant = DateTime.now();
    final joursLabels = List.generate(7, (i) {
      final date = maintenant.subtract(Duration(days: 6 - i));
      return DateFormat('E', 'fr_FR')
          .format(date)
          .substring(0, 2); // Lu, Ma, etc.
    });

    // Un maxY nul (aucune vente) fait planter le calcul d'intervalle de
    // fl_chart : on retombe sur une échelle par défaut lisible.
    final maxBrut = barGroups.isEmpty
        ? 0.0
        : barGroups
            .map((g) => g.barRods.first.toY)
            .reduce((a, b) => a > b ? a : b);
    final maxY = maxBrut <= 0 ? 100000.0 : maxBrut * 1.2;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            titre: 'Ventes des 7 derniers jours',
            icone: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: Espace.lg),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barGroups: barGroups,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  // Intervalle proportionnel : en dur (100 000) le graphe
                  // dessinait des centaines de lignes dès que le chiffre
                  // d'affaires montait.
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            index >= 0 && index < joursLabels.length
                                ? joursLabels[index]
                                : '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) {
                        if (value <= 0) return const SizedBox.shrink();
                        final masque = ref.watch(masquerMontantsProvider);
                        return Padding(
                          padding: const EdgeInsets.only(right: Espace.xs),
                          child: Text(
                            masque ? '••' : _abregerMontant(value),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final montant = rod.toY.round();
                      final masque = ref.read(masquerMontantsProvider);
                      return BarTooltipItem(
                        _fmtMontantDashboard(montant, masque),
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RaccourciAction extends StatelessWidget {
  final String label;
  final IconData icone;
  final VoidCallback onTap;

  const _RaccourciAction({
    required this.label,
    required this.icone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(Rayon.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rayon.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, color: Colors.white, size: 20),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

