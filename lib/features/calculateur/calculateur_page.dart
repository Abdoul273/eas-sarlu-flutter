import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../dashboard/dashboard_page.dart';
import 'devis_sheet.dart';

class _ItemCalculateur {
  final String id;
  final Article article;
  int quantite;
  int prixUnitaire;
  final TextEditingController qteCtrl;
  final TextEditingController prixCtrl;

  _ItemCalculateur({
    required this.id,
    required this.article,
    this.quantite = 1,
    required this.prixUnitaire,
  })  : qteCtrl = TextEditingController(text: quantite.toString()),
        prixCtrl = TextEditingController(text: prixUnitaire.toString());

  int get total => quantite * prixUnitaire;

  void dispose() {
    qteCtrl.dispose();
    prixCtrl.dispose();
  }
}

class CalculateurPage extends ConsumerStatefulWidget {
  const CalculateurPage({super.key});

  @override
  ConsumerState<CalculateurPage> createState() => _CalculateurPageState();
}

class _CalculateurPageState extends ConsumerState<CalculateurPage> {
  final List<_ItemCalculateur> _items = [];
  int _nextId = 1;

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _retourSecurise(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accueil');
    }
  }

  void _reinitialiser() {
    setState(() {
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
    });
  }

  void _ajouterArticle(Article article) {
    final existingIndex = _items.indexWhere((i) => i.article.id == article.id);
    setState(() {
      if (existingIndex != -1) {
        final item = _items[existingIndex];
        item.quantite += 1;
        item.qteCtrl.text = item.quantite.toString();
      } else {
        _items.add(_ItemCalculateur(
          id: 'item_${_nextId++}',
          article: article,
          quantite: 1,
          prixUnitaire: article.prixVente,
        ));
      }
    });
  }

  void _supprimerItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  void _ajusterQuantite(_ItemCalculateur item, int delta) {
    final nouvelleQte = (item.quantite + delta).clamp(1, 999999);
    setState(() {
      item.quantite = nouvelleQte;
      item.qteCtrl.text = nouvelleQte.toString();
    });
  }

  void _rechercherArticles() async {
    final articles = ref.read(tousArticlesProvider).valueOrNull ?? [];
    final searchCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final query = searchCtrl.text.toLowerCase().trim();
            final filtres = articles.where((a) {
              return a.nom.toLowerCase().contains(query) ||
                  a.ref.toLowerCase().contains(query) ||
                  a.categorie.toLowerCase().contains(query);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;

                return Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: Rayon.feuille,
                  ),
                  child: Column(
                    children: [
                      const PoigneeFeuille(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Espace.page),
                        child: Row(
                          children: [
                            Text(
                              'Sélectionner des articles',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.check_circle_rounded),
                              label: Text('Terminer (${_items.length})'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Espace.xs),
                      AppSearchBar(
                        controller: searchCtrl,
                        hintText: 'Rechercher par nom, réf ou catégorie…',
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: Espace.xs),
                      Expanded(
                        child: filtres.isEmpty
                            ? const EtatVide(
                                message: 'Aucun article trouvé',
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.all(Espace.page),
                                itemCount: filtres.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: Espace.xs),
                                itemBuilder: (context, index) {
                                  final article = filtres[index];
                                  // `firstOrNull` et non `firstWhere(orElse)` :
                                  // l'ancien repli construisait un item — et
                                  // ses deux contrôleurs de texte — à chaque
                                  // ligne affichée, sans jamais les libérer.
                                  final qteDansListe = _items
                                          .where((i) => i.article.id == article.id)
                                          .firstOrNull
                                          ?.quantite ??
                                      0;

                                  return AppCard(
                                    onTap: () {
                                      _ajouterArticle(article);
                                      setModalState(() {});
                                    },
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: scheme.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(Rayon.sm),
                                          ),
                                          child: Icon(
                                            Icons.inventory_2_rounded,
                                            color: scheme.primary,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: Espace.md),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      article.nom,
                                                      style: theme
                                                          .textTheme.bodyLarge
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (article.ref.isNotEmpty) ...[
                                                    const SizedBox(width: 6),
                                                    BadgePastille(
                                                      texte: article.ref,
                                                      couleur: scheme.primary,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Stock: ${article.stock} ${article.unite} • ${fmtGNF(article.prixVente)} / unité',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: Espace.xs),
                                        if (qteDansListe > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: scheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      Rayon.pilule),
                                            ),
                                            child: Text(
                                              'x$qteDansListe',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: scheme.onPrimaryContainer,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                        else
                                          IconButton.filledTonal(
                                            icon: const Icon(
                                                Icons.add_rounded,
                                                size: 18),
                                            onPressed: () {
                                              _ajouterArticle(article);
                                              setModalState(() {});
                                            },
                                            visualDensity: VisualDensity.compact,
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
          },
        );
      },
    );
  }

  void _ajouterAVente() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Veuillez ajouter au moins un article à calculer')),
      );
      return;
    }

    final payload = _items
        .map((item) => {
              'articleId': item.article.id,
              'quantite': item.quantite,
              'prixUnitaire': item.prixUnitaire,
            })
        .toList();

    context.pushNamed(
      'nouvelle-vente',
      extra: {'articles': payload},
    );
  }

  /// Le calcul, mis en lignes de document.
  ///
  /// Le prix retenu est celui qui est À L'ÉCRAN, et non le prix habituel de
  /// l'article : c'est tout l'intérêt du calculateur que de négocier avant de
  /// chiffrer, et le devis doit porter le prix négocié.
  List<LigneVente> _lignesDevis() => _items
      .where((i) => i.quantite > 0)
      .map((i) => LigneVente(
            articleId: i.article.id,
            articleRef: i.article.ref,
            articleNom: i.article.nom,
            unite: i.article.unite,
            qte: i.quantite,
            prixUnitaire: i.prixUnitaire,
            total: i.total,
          ))
      .toList();

  void _etablirDevis() {
    final lignes = _lignesDevis();
    if (lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ajoutez au moins un article avant de faire une '
                'proforma')),
      );
      return;
    }
    ouvrirFeuilleDevis(context, lignes: lignes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    int totalGeneral = 0;
    int totalUnites = 0;
    int articlesEnSurstockCount = 0;

    for (final item in _items) {
      totalGeneral += item.total;
      totalUnites += item.quantite;
      if (item.article.stock < item.quantite) {
        articlesEnSurstockCount++;
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calculateur Multi-Articles'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
          actions: [
            if (_items.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.cleaning_services_rounded),
                onPressed: _reinitialiser,
                tooltip: 'Vider le calculateur',
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Espace.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Grande Carte de Résumé des Calculs
                    Container(
                      padding: const EdgeInsets.all(Espace.lg),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.primaryContainer,
                            scheme.surfaceContainerHigh,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(Rayon.lg),
                        border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calculate_rounded,
                                  color: scheme.primary, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                'TOTAL GÉNÉRAL CALCULÉ',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSurfaceVariant,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Espace.xs),
                          Text(
                            fmtGNF(totalGeneral),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: Espace.xs),
                          Text(
                            '${_items.length} article(s) • $totalUnites unité(s) au total',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (articlesEnSurstockCount > 0) ...[
                            const SizedBox(height: Espace.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Espace.md,
                                vertical: Espace.xs,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.error.withValues(alpha: 0.14),
                                borderRadius:
                                    BorderRadius.circular(Rayon.pilule),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: 16, color: scheme.error),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Attention: Stock insuffisant pour $articlesEnSurstockCount article(s)',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.error,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Espace.md),

                    // Bouton Ajouter des Articles
                    AppButton(
                      label: _items.isEmpty
                          ? 'Choisir des articles à calculer'
                          : 'Ajouter d\'autres articles (${_items.length})',
                      icon: Icons.add_shopping_cart_rounded,
                      onPressed: _rechercherArticles,
                      isTonal: _items.isNotEmpty,
                    ),
                    const SizedBox(height: Espace.lg),

                    // Titre Liste des articles calculés
                    if (_items.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Articles à calculer (${_items.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: _reinitialiser,
                            child: const Text('Tout effacer'),
                          ),
                        ],
                      ),
                      const SizedBox(height: Espace.xs),
                    ],

                    // Cartes des Articles
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: EtatVide(
                          message: 'Calculateur vide',
                          description:
                              'Appuyez sur le bouton ci-dessus pour sélectionner un ou plusieurs articles du catalogue.',
                          icone: Icons.calculate_outlined,
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: Espace.md),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final article = item.article;
                          final enSurstock = article.stock < item.quantite;

                          return AppCard(
                            padding: const EdgeInsets.all(Espace.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // En-tête Article
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(Espace.sm),
                                      decoration: BoxDecoration(
                                        color: scheme.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(Rayon.sm),
                                      ),
                                      child: Icon(
                                        Icons.inventory_2_rounded,
                                        color: scheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: Espace.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  article.nom,
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (article.ref.isNotEmpty) ...[
                                                const SizedBox(width: 6),
                                                BadgePastille(
                                                  texte: article.ref,
                                                  couleur: scheme.primary,
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Stock: ${article.stock} ${article.unite} • Prix hab.: ${fmtGNF(article.prixVente)}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: scheme.error,
                                      ),
                                      onPressed: () => _supprimerItem(index),
                                      tooltip: 'Retirer',
                                    ),
                                  ],
                                ),
                                if (enSurstock) ...[
                                  const SizedBox(height: Espace.xs),
                                  Text(
                                    'Stock dispo (${article.stock}) inférieur à la demande (${item.quantite})',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.error,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                                const Divider(height: Espace.md),

                                // Contrôles Quantité & Prix Unitaire
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Champ Quantité
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'QUANTITÉ',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          TextField(
                                            controller: item.qteCtrl,
                                            keyboardType: TextInputType.number,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            decoration: InputDecoration(
                                              suffixText: article.unite.isEmpty
                                                  ? 'unités'
                                                  : article.unite,
                                              border: const OutlineInputBorder(),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 8,
                                              ),
                                            ),
                                            onChanged: (val) {
                                              final n = int.tryParse(val) ?? 1;
                                              setState(() {
                                                item.quantite = n;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: Espace.md),

                                    // Champ Prix Unitaire
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'PRIX UNIT. (GNF)',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          TextField(
                                            controller: item.prixCtrl,
                                            keyboardType: TextInputType.number,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            decoration: const InputDecoration(
                                              suffixText: 'GNF',
                                              border: OutlineInputBorder(),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 8,
                                              ),
                                            ),
                                            onChanged: (val) {
                                              final p = parseMontantClean(val);
                                              setState(() {
                                                item.prixUnitaire = p;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: Espace.xs),

                                // Quick Modifiers (-1, +1, +10, +50)
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      ActionChip(
                                        label: const Text('-1'),
                                        onPressed: () =>
                                            _ajusterQuantite(item, -1),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      const SizedBox(width: 4),
                                      ActionChip(
                                        label: const Text('+1'),
                                        onPressed: () =>
                                            _ajusterQuantite(item, 1),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      const SizedBox(width: 4),
                                      ActionChip(
                                        label: const Text('+10'),
                                        onPressed: () =>
                                            _ajusterQuantite(item, 10),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      const SizedBox(width: 4),
                                      ActionChip(
                                        label: const Text('+50'),
                                        onPressed: () =>
                                            _ajusterQuantite(item, 50),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      const SizedBox(width: 4),
                                      ActionChip(
                                        label: const Text('+100'),
                                        onPressed: () =>
                                            _ajusterQuantite(item, 100),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: Espace.xs),

                                // Sous-total de la ligne
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Espace.md,
                                    vertical: Espace.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerLowest,
                                    borderRadius:
                                        BorderRadius.circular(Rayon.sm),
                                    border:
                                        Border.all(color: scheme.outlineVariant),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Sous-total article',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        fmtGNF(item.total),
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Bar d'Action Fixe en Bas
            if (_items.isNotEmpty)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(Espace.page),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  // Deux issues au calcul, et elles ne se valent pas : le devis
                  // est un papier qu'on envoie et qui n'engage rien, la vente
                  // touche au stock et à la caisse. La première est proposée en
                  // second plan, la seconde reste le geste principal.
                  child: Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Proforma',
                          icon: Icons.description_outlined,
                          onPressed: _etablirDevis,
                          isTonal: true,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: Espace.sm),
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          label: 'Créer la vente (${fmtGNF(totalGeneral)})',
                          icon: Icons.add_shopping_cart_rounded,
                          onPressed: _ajouterAVente,
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
