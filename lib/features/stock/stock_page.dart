import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../dashboard/dashboard_page.dart'; // pour accès aux providers communs

// Provider local pour les articles filtrés par recherche
final articlesFiltresProvider =
    Provider.family<List<Article>, String>((ref, query) {
  final articlesAsync = ref.watch(tousArticlesProvider);
  return articlesAsync.valueOrNull?.where((a) {
        if (query.isEmpty) return true;
        final q = query.toLowerCase().trim();
        return a.nom.toLowerCase().contains(q) ||
            a.ref.toLowerCase().contains(q) ||
            a.categorie.toLowerCase().contains(q);
      }).toList() ??
      [];
});

// Provider pour la liste des catégories distinctes
final categoriesProvider = Provider<List<String>>((ref) {
  final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];
  return articles
      .map((a) => a.categorie)
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
});

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _categorieFiltre;
  String _tri = 'nom';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final articles = ref.watch(articlesFiltresProvider(_query));
    final categories = ref.watch(categoriesProvider);
    final articlesAlerte = ref.watch(articlesAlerteProvider);
    final voitPrixAchat =
        ref.watch(utilisateurActuelProvider)?.voitPrixAchat ?? false;

    var filtres = articles;
    if (_categorieFiltre != null) {
      filtres = filtres.where((a) => a.categorie == _categorieFiltre).toList();
    }

    switch (_tri) {
      case 'nom':
        filtres.sort((a, b) => a.nom.compareTo(b.nom));
        break;
      case 'stock':
        filtres.sort((a, b) => a.stock.compareTo(b.stock));
        break;
      case 'valeur':
        filtres.sort(
            (a, b) => (b.prixVente * b.stock).compareTo(a.prixVente * a.stock));
        break;
    }

    return Column(
      children: [
        AppSearchBar(
          controller: _searchController,
          hintText: 'Rechercher un article…',
          onChanged: (v) => setState(() => _query = v),
        ),
        if (articlesAlerte.isNotEmpty) _BandeauAlerte(nombre: articlesAlerte.length),

        // Barre de filtres. La hauteur n'est plus imposée : le chip mesure
        // lui-même sa hauteur (elle dépend de la police système), et un
        // SizedBox trop court la rognait — c'est l'origine des débordements ici.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
              Espace.page, Espace.xs, Espace.page, Espace.sm),
          child: Row(
            children: [
              _ChipCategorie(
                label: 'Toutes',
                selectionne: _categorieFiltre == null,
                onTap: () => setState(() => _categorieFiltre = null),
              ),
              for (final cat in categories) ...[
                const SizedBox(width: Espace.sm),
                _ChipCategorie(
                  label: cat,
                  selectionne: _categorieFiltre == cat,
                  onTap: () => setState(() => _categorieFiltre = cat),
                ),
              ],
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
              Espace.page, 0, Espace.page, Espace.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${filtres.length} article(s)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Icon(Icons.swap_vert_rounded,
                  size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: Espace.xs),
              DropdownButton<String>(
                value: _tri,
                underline: const SizedBox.shrink(),
                isDense: true,
                borderRadius: BorderRadius.circular(Rayon.md),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                items: const [
                  DropdownMenuItem(value: 'nom', child: Text('Nom')),
                  DropdownMenuItem(value: 'stock', child: Text('Stock')),
                  DropdownMenuItem(value: 'valeur', child: Text('Valeur')),
                ],
                onChanged: (v) => setState(() => _tri = v!),
              ),
            ],
          ),
        ),

        Expanded(
          child: filtres.isEmpty
              ? const EtatVide(
                  icone: Icons.inventory_2_outlined,
                  message: 'Aucun article trouvé',
                  description: 'Modifiez la recherche ou le filtre de catégorie.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: Espace.basDeListe),
                  itemCount: filtres.length,
                  itemBuilder: (context, index) {
                    final article = filtres[index];
                    return _ArticleCard(
                      article: article,
                      voitPrixAchat: voitPrixAchat,
                      onTap: () => context.pushNamed('detail-article',
                          pathParameters: {'id': article.id}),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Bandeau d'avertissement en tête de liste.
class _BandeauAlerte extends StatelessWidget {
  final int nombre;
  const _BandeauAlerte({required this.nombre});

  @override
  Widget build(BuildContext context) {
    final metier = context.metier;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          Espace.page, 0, Espace.page, Espace.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: Espace.md, vertical: Espace.sm + 2),
      decoration: BoxDecoration(
        color: metier.alerteFond,
        borderRadius: BorderRadius.circular(Rayon.md),
        border: Border.all(color: metier.alerte.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: metier.alerte, size: 19),
          const SizedBox(width: Espace.sm),
          Expanded(
            child: Text(
              '$nombre article(s) sous le seuil d\'alerte',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: metier.alerte,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de filtre par catégorie, dimensionné par son contenu.
class _ChipCategorie extends StatelessWidget {
  final String label;
  final bool selectionne;
  final VoidCallback onTap;

  const _ChipCategorie({
    required this.label,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selectionne
          ? scheme.primary.withValues(alpha: 0.13)
          : scheme.surfaceContainerLow,
      shape: StadiumBorder(
        side: BorderSide(
          color: selectionne ? scheme.primary : scheme.outlineVariant,
          width: selectionne ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Espace.md + 2, vertical: Espace.sm + 1),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.15,
              fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500,
              color: selectionne ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final Article article;
  final bool voitPrixAchat;
  final VoidCallback onTap;

  const _ArticleCard(
      {required this.article,
      required this.voitPrixAchat,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metier = context.metier;
    final stockColor = article.stock <= 0
        ? metier.danger
        : article.stock <= article.stockMin
            ? metier.alerte
            : metier.succes;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Espace.md),
      child: Row(
        children: [
          if (bytesFromBase64(article.photo) != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Rayon.md),
              child: Image.memory(
                bytesFromBase64(article.photo)!,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _categoryAvatar(),
              ),
            )
          else
            _categoryAvatar(),
          const SizedBox(width: Espace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  article.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${article.ref.isNotEmpty ? article.ref : "Sans réf"} • ${article.categorie.isEmpty ? "Sans catégorie" : article.categorie}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Espace.xs),
                Text(
                  fmtGNF(article.prixVente),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Espace.sm),
          // Colonne de droite bornée : sans contrainte, une unité longue
          // (« sacs de 50 kg ») écrasait le nom de l'article.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                BadgePastille(
                  texte: '${article.stock} ${article.unite}',
                  couleur: stockColor,
                ),
                if (voitPrixAchat)
                  Padding(
                    padding: const EdgeInsets.only(top: Espace.xs),
                    child: Text(
                      'Achat ${fmtGNF(article.prixAchat)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryAvatar() {
    final couleur = _categorieColor(article.categorie);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Rayon.md),
      ),
      child: Center(
        child: Icon(Icons.inventory_2_rounded, size: 22, color: couleur),
      ),
    );
  }

  Color _categorieColor(String categorie) {
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.brown,
      Colors.deepOrange,
      Colors.pink,
      Colors.lime,
    ];
    return colors[categorie.hashCode.abs() % colors.length];
  }
}
