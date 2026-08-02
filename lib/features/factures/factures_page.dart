import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../ventes/ventes_page.dart'; // pour clientMapProvider
import '../dashboard/dashboard_page.dart'; // pour toutesFacturesProvider, masquerMontantsProvider

// Provider pour le total impayé
final totalImpayeProvider = Provider<int>((ref) {
  final factures = ref.watch(toutesFacturesProvider).valueOrNull ?? [];
  return factures
      .where((f) => resteDu(f) > 0)
      .fold<int>(0, (sum, f) => sum + resteDu(f));
});

class FacturesPage extends ConsumerStatefulWidget {
  const FacturesPage({super.key});

  @override
  ConsumerState<FacturesPage> createState() => _FacturesPageState();
}

class _FacturesPageState extends ConsumerState<FacturesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';
  String _tri = 'date'; // 'date' ou 'resteDu'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(
        () => setState(() => _query = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Facture> _filtrerEtTrier(List<Facture> factures, String statutFiltre) {
    final clientMap = ref.read(clientMapProvider);
    var filtrees = factures.where((f) {
      if (_query.isNotEmpty) {
        final client = clientMap[f.clientId];
        final q = _query.toLowerCase();
        return f.numero.toLowerCase().contains(q) ||
            (client?.nom.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();

    if (statutFiltre == 'payée') {
      filtrees = filtrees.where((f) => resteDu(f) <= 0).toList();
    } else if (statutFiltre == 'non payée') {
      filtrees = filtrees.where((f) => resteDu(f) > 0).toList();
    }

    switch (_tri) {
      case 'date':
        filtrees.sort((a, b) => b.dateEmission.compareTo(a.dateEmission));
        break;
      case 'resteDu':
        filtrees.sort((a, b) => resteDu(b).compareTo(resteDu(a)));
        break;
    }
    return filtrees;
  }

  @override
  Widget build(BuildContext context) {
    final facturesAsync = ref.watch(toutesFacturesProvider);
    final factures = facturesAsync.valueOrNull ?? [];
    final totalImpaye = ref.watch(totalImpayeProvider);
    final masque = ref.watch(masquerMontantsProvider);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Métriques globales pour le Header
    final totalFactureTTC =
        factures.fold<int>(0, (sum, f) => sum + f.montantTTC);

    return Column(
      children: [
        // En-tête Hero Gradient Marque (Identique à Accueil & Ventes)
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Espace.page, Espace.sm, Espace.page, Espace.xs),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Espace.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Rayon.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  Color.lerp(scheme.primary, const Color(0xFFE85D04), 0.5)!,
                  const Color(0xFFC23E00),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.receipt_long_rounded,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: Espace.md),
                        const Text(
                          'Journal des Factures',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${factures.length} facture(s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Row(
                  children: [
                    Expanded(
                      child: _HeaderStatItem(
                        label: 'Total Facturé (TTC)',
                        valeur: masque ? '•••• GNF' : fmtGNF(totalFactureTTC),
                        icone: Icons.receipt_rounded,
                      ),
                    ),
                    Container(
                        height: 36,
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.25)),
                    Expanded(
                      child: _HeaderStatItem(
                        label: 'Reste à recouvrir',
                        valeur: masque ? '•••• GNF' : fmtGNF(totalImpaye),
                        icone: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Barre de recherche & Filtres
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espace.page),
          child: Row(
            children: [
              Expanded(
                child: AppSearchBar(
                  controller: _searchController,
                  hintText: 'Rechercher par numéro ou client…',
                ),
              ),
              const SizedBox(width: Espace.xs + 2),
              PopupMenuButton<String>(
                initialValue: _tri,
                tooltip: 'Trier la liste',
                onSelected: (v) => setState(() => _tri = v),
                icon: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(Rayon.md),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Icon(Icons.sort_rounded,
                      size: 20, color: scheme.primary),
                ),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'date',
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 16),
                        SizedBox(width: 8),
                        Text('Trier par Date (récentes)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'resteDu',
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16),
                        SizedBox(width: 8),
                        Text('Trier par Reste dû'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Espace.xs),

        // TabBar
        TabBar(
          controller: _tabController,
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          indicatorColor: scheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Toutes'),
            Tab(text: 'Non payées'),
            Tab(text: 'Payées'),
          ],
        ),

        Expanded(
          child: facturesAsync.when(
            data: (facturesList) => TabBarView(
              controller: _tabController,
              children: [
                _buildListe(
                    context, _filtrerEtTrier(facturesList, 'toutes'), null),
                _buildListe(context, _filtrerEtTrier(facturesList, 'non payée'),
                    totalImpaye),
                _buildListe(
                    context, _filtrerEtTrier(facturesList, 'payée'), null),
              ],
            ),
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            error: (e, _) => Center(
              child: Text('Erreur: $e', style: TextStyle(color: scheme.error)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListe(
      BuildContext context, List<Facture> factures, int? totalImpaye) {
    if (factures.isEmpty) {
      return const EtatVide(
        icone: Icons.receipt_long_outlined,
        message: 'Aucune facture trouvée',
        description: 'Les factures émises apparaîtront dans cette liste.',
      );
    }
    final metier = context.metier;

    return Column(
      children: [
        if (totalImpaye != null && totalImpaye > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(
                Espace.page, Espace.sm, Espace.page, Espace.xs),
            padding: const EdgeInsets.symmetric(
                horizontal: Espace.md, vertical: Espace.sm + 2),
            decoration: BoxDecoration(
              color: metier.dangerFond,
              borderRadius: BorderRadius.circular(Rayon.md),
              border: Border.all(color: metier.danger.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: metier.danger),
                const SizedBox(width: Espace.sm),
                Expanded(
                  child: Text(
                    'Total des impayés',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: metier.danger,
                        ),
                  ),
                ),
                const SizedBox(width: Espace.sm),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      fmtGNF(totalImpaye),
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: metier.danger,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(
                top: Espace.xs, bottom: Espace.basDeListe),
            itemCount: factures.length,
            itemBuilder: (context, index) {
              final facture = factures[index];
              return _FactureCard(facture: facture);
            },
          ),
        ),
      ],
    );
  }
}

class _HeaderStatItem extends StatelessWidget {
  final String label;
  final String valeur;
  final IconData icone;

  const _HeaderStatItem({
    required this.label,
    required this.valeur,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            valeur,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _FactureCard extends ConsumerWidget {
  final Facture facture;
  const _FactureCard({required this.facture});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientMap = ref.watch(clientMapProvider);
    final client = clientMap[facture.clientId];
    final reste = resteDu(facture);
    final estPayee = reste <= 0;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;
    final couleurStatut = estPayee ? metier.succes : metier.danger;

    return AppCard(
      onTap: () => context
          .pushNamed('detail-facture', pathParameters: {'id': facture.id}),
      padding: const EdgeInsets.all(Espace.md),
      accent: couleurStatut,
      child: Row(
        children: [
          // Icon Pill Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: couleurStatut.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Rayon.md),
            ),
            child: Icon(
              estPayee
                  ? Icons.check_circle_outline_rounded
                  : Icons.receipt_long_rounded,
              color: couleurStatut,
              size: 22,
            ),
          ),
          const SizedBox(width: Espace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        facture.numero,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: Espace.sm),
                    BadgePastille(
                      texte: estPayee ? 'Payée' : 'Impayée',
                      couleur: couleurStatut,
                      icone: estPayee
                          ? Icons.check_circle_rounded
                          : Icons.warning_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        client?.nom ?? 'Client inconnu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Émise le ${fmtDateCourtIso(facture.dateEmission)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Espace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    fmtGNF(facture.montantTTC),
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (!estPayee) ...[
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: metier.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                      ),
                      child: Text(
                        'Reste ${fmtGNF(reste)}',
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: metier.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
        ],
      ),
    );
  }
}
