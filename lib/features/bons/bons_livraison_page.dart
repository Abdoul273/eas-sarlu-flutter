import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../dashboard/dashboard_page.dart'; // toutesVentesProvider
import '../ventes/ventes_page.dart'; // tousClientsProvider, entrepriseProvider, clientMapProvider
import 'bon_pdf.dart';

// Utilitaire : transformer un numéro de vente en numéro de bon
String _numeroBL(String numeroVente) {
  if (numeroVente.isEmpty) return 'BL-...';
  return numeroVente.replaceFirst('VTE', 'BL');
}

// Provider filtré/trié pour la liste des bons
final bonsLivraisonProvider =
    Provider.family<List<Vente>, String>((ref, query) {
  final ventesAsync = ref.watch(toutesVentesProvider);
  final ventes = ventesAsync.valueOrNull ?? [];
  final clientMap = ref.watch(clientMapProvider);

  var filtrees = ventes.where((v) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final client = clientMap[v.clientId];
    return _numeroBL(v.numero).toLowerCase().contains(q) ||
        (client?.nom.toLowerCase().contains(q) ?? false);
  }).toList();

  filtrees.sort((a, b) => b.date.compareTo(a.date));
  return filtrees;
});

/// Facture liée à une vente, indexée par identifiant de vente. Le bon de
/// livraison reprend les montants de la facture — comme sur le papier du
/// magasin, où les deux documents portent le même total.
final factureParVenteProvider = Provider<Map<String, Facture>>((ref) {
  final factures = ref.watch(toutesFacturesProvider).valueOrNull ?? [];
  return {for (final f in factures) f.venteId: f};
});

class BonsLivraisonPage extends ConsumerStatefulWidget {
  const BonsLivraisonPage({super.key});

  @override
  ConsumerState<BonsLivraisonPage> createState() => _BonsLivraisonPageState();
}

class _BonsLivraisonPageState extends ConsumerState<BonsLivraisonPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final bons = ref.watch(bonsLivraisonProvider(_query));
    final clientMap = ref.watch(clientMapProvider);

    // Métriques rapides
    final totalBons = bons.length;
    final totalArticles = bons.fold<int>(
        0, (sum, v) => sum + v.lignes.fold<int>(0, (s, l) => s + l.qte));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bons de Livraison'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _ouvrirNouveauBonSheet(context),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouveau Bon',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Column(
          children: [
            // KPI Summary Header Card (Style Factures)
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
                      scheme.primaryContainer,
                      scheme.surfaceContainerHigh,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Rayon.md),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Bons Émis',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$totalBons bon(s)',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: scheme.outlineVariant,
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Articles à Livrer',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$totalArticles unité(s)',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Barre de recherche
            AppSearchBar(
              controller: _searchController,
              hintText: 'Rechercher par n° BL ou client…',
            ),

            Expanded(
              child: bons.isEmpty
                  ? const EtatVide(
                      icone: Icons.local_shipping_outlined,
                      message: 'Aucun bon de livraison',
                      description:
                          'Les bons de livraison générés à partir des ventes s\'afficheront ici.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: bons.length,
                      itemBuilder: (context, index) {
                        final vente = bons[index];
                        final client = clientMap[vente.clientId];
                        return _BonCard(
                          vente: vente,
                          client: client,
                          onTap: () => _afficherDetail(context, vente, client),
                          onPdf: () => _partagerPdf(context, vente, client),
                          onImprimer: () =>
                              _imprimerPdf(context, vente, client),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _afficherDetail(BuildContext context, Vente vente, Client? client) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _BonDetailSheet(vente: vente, client: client),
    );
  }

  void _ouvrirNouveauBonSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NouveauBonSheet(),
    );
  }

  void _partagerPdf(BuildContext context, Vente vente, Client? client) {
    final entreprise = ref.read(entrepriseProvider).valueOrNull;
    final facture = ref.read(factureParVenteProvider)[vente.id];
    partagerBonPdf(vente, client, entreprise, facture: facture);
  }

  void _imprimerPdf(BuildContext context, Vente vente, Client? client) {
    final entreprise = ref.read(entrepriseProvider).valueOrNull;
    final facture = ref.read(factureParVenteProvider)[vente.id];
    imprimerBonPdf(vente, client, entreprise, facture: facture);
  }
}

// Carte dans la liste avec design identique à FactureCard
class _BonCard extends StatelessWidget {
  final Vente vente;
  final Client? client;
  final VoidCallback onTap;
  final VoidCallback onPdf;
  final VoidCallback onImprimer;

  const _BonCard({
    required this.vente,
    required this.client,
    required this.onTap,
    required this.onPdf,
    required this.onImprimer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final numeroBL = _numeroBL(vente.numero);
    final totalQte = vente.lignes.fold<int>(0, (sum, ligne) => sum + ligne.qte);

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
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Rayon.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_shipping_rounded,
                        size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      numeroBL,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                fmtDateCourtIso(vente.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.sm),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Espace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client?.nom ?? 'Client de passage',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${vente.lignes.length} article(s) • $totalQte unité(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.sm),
          const Divider(height: 1),
          const SizedBox(height: Espace.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: onPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('Partager PDF'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.print_rounded, size: 20),
                onPressed: onImprimer,
                tooltip: 'Imprimer',
                color: scheme.primary,
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ],
      ),
    );
  }
}

// Modale de sélection d'une vente pour générer un nouveau bon de livraison
class _NouveauBonSheet extends ConsumerWidget {
  const _NouveauBonSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ventesAsync = ref.watch(toutesVentesProvider);
    final ventes = ventesAsync.valueOrNull ?? [];
    final clientMap = ref.watch(clientMapProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: Rayon.feuille,
          ),
          child: Column(
            children: [
              const PoigneeFeuille(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Espace.sm),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Rayon.sm),
                      ),
                      child: Icon(Icons.add_shopping_cart_rounded,
                          color: scheme.primary),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Générer un Bon de Livraison',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Sélectionnez une vente pour émettre son bon',
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
              const SizedBox(height: Espace.sm),
              const Divider(),
              Expanded(
                child: ventes.isEmpty
                    ? const EtatVide(
                        message: 'Aucune vente disponible',
                        description:
                            'Effectuez d\'abord une vente pour générer un bon de livraison.',
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(Espace.page),
                        itemCount: ventes.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: Espace.sm),
                        itemBuilder: (context, index) {
                          final v = ventes[index];
                          final client = clientMap[v.clientId];
                          final blNo = _numeroBL(v.numero);

                          return AppCard(
                            onTap: () {
                              Navigator.of(context).pop();
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: false,
                                backgroundColor: Colors.transparent,
                                builder: (_) =>
                                    _BonDetailSheet(vente: v, client: client),
                              );
                            },
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(Espace.sm),
                                  decoration: BoxDecoration(
                                    color:
                                        scheme.primary.withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(Rayon.sm),
                                  ),
                                  child: Icon(Icons.receipt_long_rounded,
                                      color: scheme.primary),
                                ),
                                const SizedBox(width: Espace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        blNo,
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        client?.nom ?? 'Client de passage',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      Text(
                                        'Date : ${fmtDateCourtIso(v.date)}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AppButton(
                                  label: 'Émettre',
                                  icon: Icons.check_circle_outline_rounded,
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      showDragHandle: false,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => _BonDetailSheet(
                                          vente: v, client: client),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Feuille de détail avec possibilité de modifier les quantités pour le bon
class _BonDetailSheet extends ConsumerStatefulWidget {
  final Vente vente;
  final Client? client;

  const _BonDetailSheet({required this.vente, required this.client});

  @override
  ConsumerState<_BonDetailSheet> createState() => _BonDetailSheetState();
}

class _BonDetailSheetState extends ConsumerState<_BonDetailSheet> {
  late List<int> _quantites;

  @override
  void initState() {
    super.initState();
    _quantites = widget.vente.lignes.map((l) => l.qte).toList();
  }

  Vente get _venteAjustee {
    final nouvellesLignes = <LigneVente>[];
    for (int i = 0; i < widget.vente.lignes.length; i++) {
      if (_quantites[i] > 0) {
        final l = widget.vente.lignes[i];
        nouvellesLignes.add(LigneVente(
          articleId: l.articleId,
          articleRef: l.articleRef,
          articleNom: l.articleNom,
          unite: l.unite,
          prixUnitaire: l.prixUnitaire,
          remise: l.remise,
          total: l.total,
          prixAchat: l.prixAchat,
          qte: _quantites[i],
        ));
      }
    }
    return Vente(
      id: widget.vente.id,
      numero: widget.vente.numero,
      clientId: widget.vente.clientId,
      vendeur: widget.vente.vendeur,
      date: widget.vente.date,
      lignes: nouvellesLignes,
      remiseGlobale: widget.vente.remiseGlobale,
      totalHT: widget.vente.totalHT,
      totalNet: widget.vente.totalNet,
      note: widget.vente.note,
      rev: widget.vente.rev,
      updatedAt: widget.vente.updatedAt,
      updatedBy: widget.vente.updatedBy,
    );
  }

  Future<void> _saisirQuantite(int index) async {
    final l = widget.vente.lignes[index];
    final ctrl = TextEditingController(text: _quantites[index].toString());
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quantité à livrer'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Max: ${l.qte} ${l.unite}',
            suffixText: l.unite,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final val = parseMontantClean(ctrl.text);
              Navigator.pop(ctx, val.clamp(0, l.qte));
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (res != null && mounted) {
      setState(() {
        _quantites[index] = res;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entreprise = ref.watch(entrepriseProvider).valueOrNull;
    final facture = ref.watch(factureParVenteProvider)[widget.vente.id];
    final destinataire = widget.client;
    final blNo = _numeroBL(widget.vente.numero);
    final totalQte = _quantites.fold<int>(0, (sum, qte) => sum + qte);

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
                            child: Icon(Icons.local_shipping_rounded,
                                color: scheme.primary, size: 26),
                          ),
                          const SizedBox(width: Espace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  blNo,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Émis le ${fmtDateIso(widget.vente.date)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          BadgePastille(
                            texte: 'Bon de livraison',
                            couleur: scheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Espace.md),

                    // Destinataire Card
                    AppCard(
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INFORMATIONS DESTINATAIRE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: Espace.xs),
                          Row(
                            children: [
                              Icon(Icons.person_rounded,
                                  size: 18, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text(
                                destinataire?.nom ?? 'Client de passage',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (destinataire?.telephone != null &&
                              destinataire!.telephone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.phone_rounded,
                                    size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text(destinataire.telephone,
                                    style: theme.textTheme.bodyMedium),
                              ],
                            ),
                          ],
                          if (destinataire?.adresse != null &&
                              destinataire!.adresse.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.location_on_rounded,
                                    size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text(destinataire.adresse,
                                    style: theme.textTheme.bodyMedium),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Espace.md),

                    // Tableau des articles à livrer
                    Text(
                      'ARTICLES À LIVRER ($totalQte unité(s))',
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
                          for (int i = 0; i < widget.vente.lignes.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.all(Espace.md),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color:
                                          scheme.primary.withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(Rayon.sm),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: Espace.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.vente.lignes[i].articleNom,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Réf: ${widget.vente.lignes[i].articleRef}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(Rayon.pilule),
                                    onTap: () => _saisirQuantite(i),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: Espace.md,
                                        vertical: Espace.xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHigh,
                                        borderRadius:
                                            BorderRadius.circular(Rayon.pilule),
                                        border: Border.all(
                                          color: _quantites[i] < widget.vente.lignes[i].qte
                                              ? scheme.primary
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${_quantites[i]} ',
                                            style:
                                                theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          if (_quantites[i] < widget.vente.lignes[i].qte)
                                            Text(
                                              '/ ${widget.vente.lignes[i].qte} ',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          Text(
                                            widget.vente.lignes[i].unite,
                                            style:
                                                theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.edit_rounded,
                                            size: 14,
                                            color: scheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (i < widget.vente.lignes.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Espace.xl),

                    // Actions PDF & Imprimer
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Partager PDF',
                            icon: Icons.share_rounded,
                            onPressed: () => partagerBonPdf(
                                _venteAjustee, destinataire, entreprise,
                                facture: facture),
                            isTonal: true,
                          ),
                        ),
                        const SizedBox(width: Espace.md),
                        Expanded(
                          child: AppButton(
                            label: 'Imprimer',
                            icon: Icons.print_rounded,
                            onPressed: () => imprimerBonPdf(
                                _venteAjustee, destinataire, entreprise,
                                facture: facture),
                          ),
                        ),
                      ],
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
}
