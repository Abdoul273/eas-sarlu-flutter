import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../app/theme.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../../core/auth/auth_state.dart';
import '../../core/api/endpoints.dart';
import 'ajustement_sheet.dart';
import 'mouvement_sheet.dart';
import '../dashboard/dashboard_page.dart';
import '../ventes/vente_detail_sheet.dart';
import '../../core/reseau.dart';

// Providers
final articleStreamProvider =
    StreamProvider.family<Article?, String>((ref, id) {
  final stores = ref.watch(storesProvider);
  return stores.watchArticle(id);
});

final mouvementsArticleProvider =
    StreamProvider.family<List<MouvementStock>, String>((ref, articleId) {
  final stores = ref.watch(storesProvider);
  return stores.watchMouvementsByArticle(articleId);
});

class ArticleDetailPage extends ConsumerWidget {
  final String id;
  const ArticleDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articleAsync = ref.watch(articleStreamProvider(id));
    final mouvementsAsync = ref.watch(mouvementsArticleProvider(id));
    final utilisateur = ref.watch(utilisateurActuelProvider);
    final voitPrixAchat = utilisateur?.voitPrixAchat ?? false;
    // Consulter la fiche reste ouvert à tous ; la modifier et bouger le stock
    // exigent le droit correspondant, que le serveur vérifie de son côté.
    // Afficher les boutons sans ce droit ne mènerait qu'à un refus après coup.
    final peutEcrireStock = utilisateur?.aLeDroit('stock') ?? false;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              articleAsync.valueOrNull?.nom ?? 'Fiche Article',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (articleAsync.valueOrNull?.categorie.isNotEmpty ?? false)
              Text(
                articleAsync.valueOrNull!.categorie,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          if (peutEcrireStock) ...[
            IconButton.filledTonal(
              icon: Icon(Icons.edit_rounded, size: 20, color: scheme.primary),
              style: IconButton.styleFrom(
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
              ),
              tooltip: 'Modifier l\'article',
              onPressed: () => context
                  .pushNamed('nouvel-article', queryParameters: {'edit': id}),
            ),
            const SizedBox(width: 8),
          ],
          IconButton.filledTonal(
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: scheme.error),
            style: IconButton.styleFrom(
              backgroundColor: scheme.error.withValues(alpha: 0.12),
            ),
            tooltip: 'Supprimer',
            onPressed: () => _supprimerArticle(context, ref, id),
          ),
          const SizedBox(width: Espace.page),
        ],
      ),
      body: articleAsync.when(
        data: (article) {
          if (article == null) {
            return const EtatVide(
              icone: Icons.search_off_rounded,
              message: 'Article introuvable',
              description: 'Cet article a peut-être été supprimé du stock.',
            );
          }

          final statutStock = stockStatut(article);
          final isRupture = statutStock == 'rupture';
          final isStockBas = statutStock == 'faible';
          final margeAbs = article.prixVente - article.prixAchat;
          final pctMarge = tauxMargeArticle(article)?.round() ?? 0;

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Espace.page,
              Espace.xs,
              Espace.page,
              Espace.basDeListe,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero Banner avec Photo / Dégradé Marque & SKU Copiable
                _buildHeroBanner(context, article, isRupture, isStockBas),
                const SizedBox(height: Espace.md),

                // Jauge de santé du stock
                _buildStockHealthGauge(context, article, isRupture, isStockBas),
                const SizedBox(height: Espace.lg),

                // Cartes KPIs Financières & Stock
                _buildMetricsGrid(context, article, isRupture, isStockBas,
                    voitPrixAchat, margeAbs, pctMarge),
                const SizedBox(height: Espace.xl),

                // Actions Rapides sur le Stock
                if (peutEcrireStock) ...[
                  const SectionHeader(
                    titre: 'Opérations de Stock',
                    icone: Icons.flash_on_rounded,
                  ),
                  const SizedBox(height: Espace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          context: context,
                          label: 'Achat',
                          icon: Icons.add_business_rounded,
                          color: metier.succes,
                          onPressed: () =>
                              _achatFournisseur(context, article),
                        ),
                      ),
                      const SizedBox(width: Espace.xs + 2),
                      Expanded(
                        child: _buildActionButton(
                          context: context,
                          label: 'Vente',
                          icon: Icons.sell_rounded,
                          color: scheme.primary,
                          onPressed: () => context.pushNamed('nouvelle-vente',
                              queryParameters: {'articleId': article.id}),
                        ),
                      ),
                      const SizedBox(width: Espace.xs + 2),
                      // Le stock ne devrait bouger que par un achat ou une
                      // vente — mais il faut bien pouvoir le remettre d'aplomb
                      // quand il ne correspond plus au dépôt. Sans cette porte,
                      // une quantité tapée à 500 au lieu de 50 restait fausse
                      // pour toujours, et faussait avec elle la valeur du
                      // stock, les alertes et le coût des marchandises vendues.
                      Expanded(
                        child: _buildActionButton(
                          context: context,
                          label: 'Ajuster',
                          icon: Icons.tune_rounded,
                          color: metier.alerte,
                          onPressed: () => _ajusterInventaire(context, article),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espace.xl),
                ],

                // Fiche Technique & Spécifications
                const SectionHeader(
                  titre: 'Fiche Technique',
                  icone: Icons.inventory_rounded,
                ),
                const SizedBox(height: Espace.sm),
                _buildFicheTechniqueCard(context, article),
                const SizedBox(height: Espace.xl),

                // Historique des Mouvements de Stock
                mouvementsAsync.when(
                  data: (mouvs) => SectionHeader(
                    titre: 'Historique des Mouvements',
                    icone: Icons.history_rounded,
                    actionLabel: mouvs.isNotEmpty ? '${mouvs.length}' : null,
                  ),
                  loading: () => const SectionHeader(
                    titre: 'Historique des Mouvements',
                    icone: Icons.history_rounded,
                  ),
                  error: (_, __) => const SectionHeader(
                    titre: 'Historique des Mouvements',
                    icone: Icons.history_rounded,
                  ),
                ),
                const SizedBox(height: Espace.sm),
                mouvementsAsync.when(
                  data: (mouvs) {
                    if (mouvs.isEmpty) {
                      return const EtatVide(
                        icone: Icons.history_toggle_off_rounded,
                        message: 'Aucun mouvement enregistré',
                        description:
                            'Les entrées et sorties de cet article apparaîtront ici.',
                        compact: true,
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: mouvs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Espace.xs + 2),
                      itemBuilder: (ctx, index) {
                        final m = mouvs[index];
                        return _buildMouvementTimelineTile(
                            context, ref, m, article);
                      },
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(Espace.lg),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                  ),
                  error: (e, _) => EtatVide(
                    icone: Icons.error_outline_rounded,
                    message: 'Erreur d\'historique',
                    description: '$e',
                    compact: true,
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        error: (e, _) => Center(
          child: Text('Erreur d\'affichage: $e',
              style: TextStyle(color: scheme.error)),
        ),
      ),
    );
  }

  /// Banner Hero Média avec dégradé identique à l'Accueil / Ventes
  Widget _buildHeroBanner(
      BuildContext context, Article article, bool isRupture, bool isStockBas) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;
    final hasPhoto = article.photo.isNotEmpty;

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Rayon.carte,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: Rayon.carte,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image de fond / Gradient Marque Identique au Dashboard
            if (bytesFromBase64(article.photo) != null)
              GestureDetector(
                onTap: () => _afficherPhotoModal(context, article),
                child: Image.memory(
                  bytesFromBase64(article.photo)!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildFallbackHeader(scheme),
                ),
              )
            else
              _buildFallbackHeader(scheme),

            // Masque Dégradé pour Lisibilité du Texte
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),

            // Badges Supérieurs : Catégorie & Statut de Stock
            Positioned(
              top: Espace.md,
              left: Espace.md,
              right: Espace.md,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (article.categorie.isNotEmpty)
                    BadgePastille(
                      texte: article.categorie,
                      couleur: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: Espace.md, vertical: 5),
                    )
                  else
                    const SizedBox.shrink(),
                  BadgePastille(
                    texte: isRupture
                        ? 'Rupture de Stock'
                        : (isStockBas ? 'Stock Bas' : 'Disponible'),
                    couleur: isRupture
                        ? metier.danger
                        : (isStockBas ? metier.alerte : metier.succes),
                    icone: isRupture
                        ? Icons.error_rounded
                        : (isStockBas
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_rounded),
                    padding: const EdgeInsets.symmetric(
                        horizontal: Espace.md, vertical: 5),
                  ),
                ],
              ),
            ),

            // Titre de l'Article & Réf SKU Copiable
            Positioned(
              bottom: Espace.md + 2,
              left: Espace.md + 2,
              right: Espace.md + 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.nom,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (article.ref.isNotEmpty)
                        Material(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(Rayon.pilule),
                          child: InkWell(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: article.ref));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded,
                                          color: Colors.white, size: 18),
                                      const SizedBox(width: Espace.sm),
                                      Text(
                                          'Référence "${article.ref}" copiée !'),
                                    ],
                                  ),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(Rayon.pilule),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.copy_rounded,
                                      size: 13, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Text(
                                    'SKU: ${article.ref}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Monospace',
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (hasPhoto) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.fullscreen_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dégradé de secours aux couleurs identiques au Header Accueil (Dashboard)
  Widget _buildFallbackHeader(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, const Color(0xFFE85D04), 0.5)!,
            const Color(0xFFC23E00),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.inventory_2_rounded,
          size: 76,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  /// Visualisateur de niveau de stock avec barre de santé du stock
  Widget _buildStockHealthGauge(
      BuildContext context, Article article, bool isRupture, bool isStockBas) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final targetMax = (article.stockMin * 2.5).clamp(10, 10000).toDouble();
    final progress = (article.stock.toDouble() / targetMax).clamp(0.0, 1.0);

    final gaugeColor = isRupture
        ? metier.danger
        : (isStockBas ? metier.alerte : metier.succes);

    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(Espace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isRupture
                          ? Icons.error_outline_rounded
                          : (isStockBas
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded),
                      size: 16,
                      color: gaugeColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Niveau de stock',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Espace.sm),
              Text(
                'Min : ${article.stockMin} ${article.unite}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.xs + 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(Rayon.pilule),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Grille des tuiles KPI (Stock, Prix Vente, Prix Achat, Marge)
  Widget _buildMetricsGrid(
    BuildContext context,
    Article article,
    bool isRupture,
    bool isStockBas,
    bool voitPrixAchat,
    int margeAbs,
    int pctMarge,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                libelle: 'Stock Actuel',
                valeur: '${article.stock} ${article.unite}',
                sousTitre: isRupture
                    ? 'Rupture'
                    : (isStockBas ? 'Alerte Stock Min' : 'Stock Suffisant'),
                icone: Icons.inventory_2_rounded,
                couleurValeur: isRupture
                    ? metier.danger
                    : (isStockBas ? metier.alerte : metier.succes),
              ),
            ),
            Expanded(
              child: StatTile(
                libelle: 'Prix de Vente',
                valeur: fmtGNF(article.prixVente),
                sousTitre: 'Par ${article.unite.toLowerCase()}',
                icone: Icons.sell_rounded,
                couleurValeur: scheme.primary,
              ),
            ),
          ],
        ),
        if (voitPrixAchat) ...[
          const SizedBox(height: Espace.xs + 2),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  libelle: 'Prix d\'Achat',
                  valeur: fmtGNF(article.prixAchat),
                  sousTitre: article.fournisseur.isNotEmpty
                      ? article.fournisseur
                      : 'Coût unitaire',
                  icone: Icons.shopping_bag_rounded,
                  couleurValeur: scheme.secondary,
                ),
              ),
              Expanded(
                child: StatTile(
                  libelle: 'Marge estimée',
                  valeur: fmtGNF(margeAbs),
                  sousTitre: switch (pctMarge) {
                    > 0 => '+$pctMarge % du prix de vente',
                    < 0 => '$pctMarge % : vente à perte',
                    _ => 'Taux zéro',
                  },
                  icone: Icons.trending_up_rounded,
                  couleurValeur: margeAbs > 0 ? metier.succes : metier.danger,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Bouton d'action rapide tactile & stylisé
  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: Rayon.carte,
        child: AnimatedContainer(
          duration: Duree.rapide,
          padding: const EdgeInsets.symmetric(
            vertical: Espace.md,
            horizontal: Espace.xs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: Rayon.carte,
            border:
                Border.all(color: color.withValues(alpha: 0.28), width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Carte Fiche Technique structurée (Harmonisée avec _InfoLine dans Ventes & Clients)
  Widget _buildFicheTechniqueCard(BuildContext context, Article article) {
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(Espace.lg),
      child: Column(
        children: [
          _buildSpecItem(
            context,
            icon: Icons.label_rounded,
            label: 'Désignation',
            value: article.nom,
            iconColor: Theme.of(context).colorScheme.primary,
          ),
          const Divider(height: 18),
          _buildSpecItem(
            context,
            icon: Icons.qr_code_2_rounded,
            label: 'Référence SKU',
            value: article.ref.isNotEmpty ? article.ref : 'Non spécifiée',
            iconColor: Theme.of(context).colorScheme.primary,
            isMonospace: true,
          ),
          const Divider(height: 18),
          _buildSpecItem(
            context,
            icon: Icons.category_rounded,
            label: 'Catégorie',
            value:
                article.categorie.isNotEmpty ? article.categorie : 'Générale',
            iconColor: context.metier.info,
          ),
          const Divider(height: 18),
          _buildSpecItem(
            context,
            icon: Icons.straighten_rounded,
            label: 'Unité de mesure',
            value: article.unite,
            iconColor: Theme.of(context).colorScheme.secondary,
          ),
          // Une épaisseur à zéro n'est pas une épaisseur : c'est un article
          // enregistré avant que le magasin ne la suive. On ne l'affiche pas.
          if (article.longueur != null || article.epaisseur > 0) ...[
            const Divider(height: 18),
            _buildSpecItem(
              context,
              icon: Icons.square_foot_rounded,
              label: 'Dimensions',
              value: [
                if (article.longueur != null) 'L: ${article.longueur} m',
                if (article.epaisseur > 0) 'Ép: ${article.epaisseur} mm',
              ].join(' • '),
              iconColor: Theme.of(context).colorScheme.primary,
            ),
          ],
          if (article.provenance.isNotEmpty) ...[
            const Divider(height: 18),
            _buildSpecItem(
              context,
              icon: Icons.public_rounded,
              label: 'Provenance',
              value: article.provenance,
              iconColor: context.metier.info,
            ),
          ],
          if (article.fournisseur.isNotEmpty) ...[
            const Divider(height: 18),
            _buildSpecItem(
              context,
              icon: Icons.business_rounded,
              label: 'Fournisseur',
              value: article.fournisseur,
              iconColor: context.metier.alerte,
            ),
          ],
          if (article.description.isNotEmpty) ...[
            const Divider(height: 18),
            _buildSpecItem(
              context,
              icon: Icons.notes_rounded,
              label: 'Description',
              value: article.description,
              iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    bool isMonospace = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Rayon.sm),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: Espace.md),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
              fontFamily: isMonospace ? 'Monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Tuile d'historique de mouvement interactive avec clic vers Vente ou Entrée
  Widget _buildMouvementTimelineTile(
      BuildContext context, WidgetRef ref, MouvementStock m, Article article) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final isEntree = m.type == 'entrée';
    final isSortie = m.type == 'sortie';

    final color =
        isEntree ? metier.succes : (isSortie ? metier.danger : metier.alerte);

    final icon = isEntree
        ? Icons.add_circle_outline_rounded
        : (isSortie ? Icons.remove_circle_outline_rounded : Icons.tune_rounded);

    final sign = isEntree ? '+' : (isSortie ? '-' : '');

    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(Espace.md),
      accent: color,
      onTap: () => _onTapMouvement(context, ref, m, article),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indicator Icon Box
          Container(
            padding: const EdgeInsets.all(Espace.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Rayon.md),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: Espace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête : Type d'opération & Delta Quantité
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.type.toUpperCase(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: color,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: scheme.outline),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Espace.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                      ),
                      child: Text(
                        '$sign${m.quantite} ${article.unite}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),

                // Transition de Stock (Ex. 100 -> 125 kg)
                if (m.quantiteAvant != null && m.quantiteApres != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Stock : ',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          '${m.quantiteAvant} → ${m.quantiteApres} ${article.unite}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],


                // Fournisseur et Quartier
                if (m.fournisseurNom != null && m.fournisseurNom!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.business_rounded,
                          size: 13, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        m.fournisseurNom!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (m.fournisseurQuartier != null && m.fournisseurQuartier!.isNotEmpty) ...[
                        const SizedBox(width: Espace.sm),
                        Icon(Icons.location_on_rounded,
                            size: 13, color: metier.succes),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            m.fournisseurQuartier!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                const SizedBox(height: 6),

                // Auteur & Horodatage
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      m.utilisateur,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Icon(Icons.access_time_rounded,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      fmtDateIso(m.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                // Note facultative
                if (m.note.isNotEmpty) ...[
                  const SizedBox(height: Espace.xs + 2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Espace.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(Rayon.sm),
                    ),
                    child: Text(
                      '« ${m.note} »',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Action lors du clic sur un élément de l'historique
  void _onTapMouvement(
      BuildContext context, WidgetRef ref, MouvementStock m, Article article) {
    final type = m.type.toLowerCase();
    final toutesVentes = ref.read(toutesVentesProvider).valueOrNull ?? [];

    if (type == 'sortie') {
      Vente? venteTrouvee;

      // 1. Recherche par numéro ou ID de vente dans la note
      if (m.note.isNotEmpty) {
        for (final v in toutesVentes) {
          if ((v.numero.isNotEmpty && m.note.contains(v.numero)) ||
              (v.id.isNotEmpty && m.note.contains(v.id))) {
            venteTrouvee = v;
            break;
          }
        }
      }

      // 2. Recherche par date exacte & présence de l'article dans les lignes de la vente
      if (venteTrouvee == null) {
        for (final v in toutesVentes) {
          final contientArticle =
              v.lignes.any((l) => l.articleId == m.articleId);
          if (contientArticle && v.date == m.date) {
            venteTrouvee = v;
            break;
          }
        }
      }

      // 3. Recherche par même jour & présence de l'article
      if (venteTrouvee == null && m.date.length >= 10) {
        final jourMouv = m.date.substring(0, 10);
        for (final v in toutesVentes) {
          final contientArticle =
              v.lignes.any((l) => l.articleId == m.articleId);
          if (contientArticle && v.date.startsWith(jourMouv)) {
            venteTrouvee = v;
            break;
          }
        }
      }

      if (venteTrouvee != null) {
        // Redirection vers les détails de la vente dans un BottomSheet
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: false,
          shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          builder: (_) => VenteDetailSheet(vente: venteTrouvee!),
        );
        return;
      }
    }

    // Si c'est un mouvement d'entrée ou d'ajustement -> Feuille de détail harmonisée MouvementDetailSheet
    _afficherModalMouvementDetail(context, m, article);
  }

  /// Affichage de la feuille de détail d'un mouvement (MouvementDetailSheet)
  void _afficherModalMouvementDetail(
      BuildContext context, MouvementStock m, Article article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (_) => MouvementDetailSheet(mouvement: m, article: article),
    );
  }

  /// Modale photo grand écran
  void _afficherPhotoModal(BuildContext context, Article article) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title:
                Text(article.nom, style: const TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: InteractiveViewer(
              child: bytesFromBase64(article.photo) != null
                  ? Image.memory(
                      bytesFromBase64(article.photo)!,
                      fit: BoxFit.contain,
                    )
                  : const Icon(Icons.broken_image_rounded, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  /// Ouvre la correction du stock : comptage, casse, erreur de saisie.
  void _ajusterInventaire(BuildContext context, Article article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (_) => AjustementSheet(article: article),
    );
  }

  /// Ouvre la saisie d'une entrée de marchandise chez un fournisseur.
  void _achatFournisseur(BuildContext context, Article article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (_) => MouvementSheet(article: article),
    );
  }

  void _supprimerArticle(BuildContext context, WidgetRef ref, String id) async {
    if (!await aUneConnexion()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('La suppression nécessite une connexion active')),
      );
      return;
    }
    if (!context.mounted) return;
    // On ne supprime pas de la marchandise en la faisant disparaître du
    // catalogue : ce qu'il reste en dépôt doit d'abord sortir par un
    // ajustement, pour qu'il en reste une trace.
    final courant = await ref.read(storesProvider).getArticle(id);
    if (courant != null && courant.stock > 0) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Il reste ${fmtNombre(courant.stock)} ${courant.unite} '
            'en stock. Faites d\'abord un ajustement à zéro.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet article ?'),
        content: const Text(
            'Cette suppression retirera l\'article du catalogue ainsi que son suivi de stock.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          AppButton(
            label: 'Supprimer',
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.dio.delete('$kDataArticleDelete$id');
        final stores = ref.read(storesProvider);
        await stores.supprimerArticle(id);
        if (!context.mounted) return;
        context.pop();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression: $e')),
        );
      }
    }
  }
}

/// Feuille de détail d'un mouvement de stock (Entrée, Sortie, Ajustement)
/// Conçue selon la même architecture et le même design que [VenteDetailSheet].
class MouvementDetailSheet extends StatelessWidget {
  final MouvementStock mouvement;
  final Article article;

  const MouvementDetailSheet({
    super.key,
    required this.mouvement,
    required this.article,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final isEntree = mouvement.type == 'entrée';
    final isSortie = mouvement.type == 'sortie';

    final color =
        isEntree ? metier.succes : (isSortie ? metier.danger : metier.alerte);

    final icon = isEntree
        ? Icons.add_circle_rounded
        : (isSortie ? Icons.remove_circle_rounded : Icons.tune_rounded);

    final sign = isEntree ? '+' : (isSortie ? '-' : '');

    final titre = isEntree
        ? 'Entrée en Stock'
        : (isSortie ? 'Sortie de Stock' : 'Ajustement d\'Inventaire');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
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

              // En-tête Mouvement Banner Card (Style VenteDetailSheet)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                child: Container(
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
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Rayon.md),
                        ),
                        child: Icon(
                          icon,
                          size: 26,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titre,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            BadgePastille(
                              texte:
                                  '$sign${mouvement.quantite} ${article.unite}',
                              couleur: color,
                              icone: icon,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Espace.md),

              // Contenu défilable
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Meta Info (Article, Référence, Stock, Date, Opérateur, Note)
                      AppCard(
                        margin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            _MouvementInfoLine(
                              icone: Icons.inventory_2_rounded,
                              label: 'Article',
                              valeur: article.nom,
                              couleurIcone: scheme.primary,
                            ),
                            if (article.ref.isNotEmpty) ...[
                              const Divider(height: 16),
                              _MouvementInfoLine(
                                icone: Icons.qr_code_2_rounded,
                                label: 'Référence SKU',
                                valeur: article.ref,
                                couleurIcone: scheme.primary,
                              ),
                            ],
                            if (mouvement.fournisseurNom != null && mouvement.fournisseurNom!.isNotEmpty) ...[
                              const Divider(height: 16),
                              _MouvementInfoLine(
                                icone: Icons.business_rounded,
                                label: 'Fournisseur',
                                valeur: mouvement.fournisseurNom!,
                                couleurIcone: metier.info,
                              ),
                            ],
                            if (mouvement.fournisseurQuartier != null && mouvement.fournisseurQuartier!.isNotEmpty) ...[
                              const Divider(height: 16),
                              _MouvementInfoLine(
                                icone: Icons.location_on_rounded,
                                label: 'Lieu / Quartier d\'enlèvement',
                                valeur: mouvement.fournisseurQuartier!,
                                couleurIcone: metier.succes,
                              ),
                            ],
                            if (mouvement.quantiteAvant != null &&
                                mouvement.quantiteApres != null) ...[
                              const Divider(height: 16),
                              _MouvementInfoLine(
                                icone: Icons.swap_horiz_rounded,
                                label: 'Évolution du stock',
                                valeur:
                                    '${mouvement.quantiteAvant} → ${mouvement.quantiteApres} ${article.unite}',
                                couleurIcone: metier.info,
                              ),
                            ],
                            const Divider(height: 16),
                            _MouvementInfoLine(
                              icone: Icons.calendar_today_rounded,
                              label: 'Date & heure',
                              valeur:
                                  '${fmtDateCourtIso(mouvement.date)} à ${fmtHeureIso(mouvement.date)}',
                              couleurIcone: scheme.secondary,
                            ),
                            if (mouvement.utilisateur.isNotEmpty) ...[
                              const Divider(height: 16),
                              _MouvementInfoLine(
                                icone: Icons.person_rounded,
                                label: 'Opérateur responsable',
                                valeur: mouvement.utilisateur,
                                couleurIcone: metier.info,
                              ),
                            ],
                            if (mouvement.note.isNotEmpty) ...[
                              const Divider(height: 16),
                              _MouvementInfoLine(
                                icone: Icons.notes_rounded,
                                label: 'Note / Remarque',
                                valeur: mouvement.note,
                                couleurIcone: metier.alerte,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: Espace.lg),
                    ],
                  ),
                ),
              ),

              // Barre d'Action Inférieure
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(Espace.page),
                  child: isSortie
                      ? AppButton(
                          label: 'Consulter le journal des ventes',
                          icon: Icons.point_of_sale_rounded,
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).pop();
                            context.goNamed('ventes');
                          },
                          expanded: true,
                        )
                      : AppButton(
                          label: 'Fermer',
                          icon: Icons.check_circle_outline_rounded,
                          onPressed: () => Navigator.pop(context),
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
}

class _MouvementInfoLine extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valeur;
  final Color couleurIcone;

  const _MouvementInfoLine({
    required this.icone,
    required this.label,
    required this.valeur,
    required this.couleurIcone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: couleurIcone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Rayon.sm),
          ),
          child: Icon(icone, size: 16, color: couleurIcone),
        ),
        const SizedBox(width: Espace.sm),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            valeur,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
