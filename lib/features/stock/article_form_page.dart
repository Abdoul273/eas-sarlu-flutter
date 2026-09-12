import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/db/stores.dart';
import '../../core/sync/op_queue.dart';
import '../dashboard/dashboard_page.dart'
    show tousArticlesProvider, utilisateurActuelProvider;
import '../fournisseurs/selecteur_fournisseur.dart';

class ArticleFormPage extends ConsumerStatefulWidget {
  const ArticleFormPage({super.key});

  @override
  ConsumerState<ArticleFormPage> createState() => _ArticleFormPageState();
}

/// D'où vient le stock qu'on déclare en créant un article.
///
/// Deux cas, et deux seulement, qui n'entraînent pas les mêmes écritures :
///
///   — [dejaEnMagasin] : la marchandise était là avant que l'application ne
///     l'enregistre. Elle a déjà été payée, il y a des mois peut-être. Aucune
///     dette fournisseur ne doit en naître, et l'attribuer à quelqu'un
///     inventerait un historique d'achat.
///   — [livraisonFournisseur] : elle vient d'arriver, de chez quelqu'un
///     d'identifié. Elle entre dans l'historique de ce fournisseur, et le
///     magasin lui doit peut-être encore de l'argent.
enum OrigineStock { dejaEnMagasin, livraisonFournisseur }

class _ArticleFormPageState extends ConsumerState<ArticleFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomCtrl,
      _refCtrl,
      _descCtrl,
      _prixAchatCtrl,
      _prixVenteCtrl,
      _stockCtrl,
      _stockMinCtrl,
      _fournisseurCtrl,
      _longueurCtrl,
      _epaisseurCtrl;
  String _categorie = 'Tube carré';
  String _unite = 'Barre';
  String _provenance = 'Turquie';
  String? _photoBase64;
  String? _editId;
  bool _isLoading = false;

  /// D'où vient le stock initial saisi à la création.
  ///
  /// La question n'est pas cosmétique : elle décide de ce qui sera écrit au
  /// journal des mouvements. Jusqu'ici le stock initial était posé directement
  /// dans la fiche, sans aucune trace — l'historique de l'article restait vide
  /// alors qu'il y avait cinquante barres en dépôt, et personne ne pouvait plus
  /// dire d'où elles venaient.
  OrigineStock _origineStock = OrigineStock.dejaEnMagasin;
  Fournisseur? _fournisseurLivraison;

  /// Quantité initiale saisie, relue à chaque frappe pour n'afficher la
  /// question de l'origine que lorsqu'elle se pose.
  int _stockInitial = 0;
  final List<String> _customCategories = [];

  static const List<String> categories = [
    'Tube carré',
    'Tube rond',
    'Tube rectangulaire',
    'IPN',
    'UPN',
    'Fer H (HEA/HEB)',
    'Cornière',
    'Fer plat',
    'Fer à béton',
    'Tôle noire',
    'Tôle galvanisée',
    'Tôle ondulée'
  ];

  List<String> get _categoriesDisponibles {
    final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];
    final catsDuStock = articles
        .map((a) => a.categorie.trim())
        .where((c) => c.isNotEmpty);
    final allSet = <String>{
      ...categories,
      ...catsDuStock,
      ..._customCategories,
      if (_categorie.trim().isNotEmpty) _categorie.trim(),
    };
    return allSet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
  static const List<String> unites = ['Barre', 'Plaque', 'Feuille'];
  static const List<String> provenances = [
    'Turquie',
    'Chine',
    'Ukraine',
    'Espagne',
    'Inde'
  ];

  @override
  void initState() {
    super.initState();
    _nomCtrl = TextEditingController();
    _refCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _prixAchatCtrl = TextEditingController();
    _prixVenteCtrl = TextEditingController();
    _stockCtrl = TextEditingController(text: '0');
    _stockCtrl.addListener(() {
      final v = parseMontantClean(_stockCtrl.text);
      if (v != _stockInitial) setState(() => _stockInitial = v);
    });
    _stockMinCtrl = TextEditingController(text: '0');
    _fournisseurCtrl = TextEditingController();
    _longueurCtrl = TextEditingController();
    _epaisseurCtrl = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editId = GoRouterState.of(context).uri.queryParameters['edit'];
      if (editId != null) {
        _editId = editId;
        _chargerArticle(editId);
      }
    });
  }

  void _chargerArticle(String id) async {
    final stores = ref.read(storesProvider);
    final article = await stores.getArticle(id);
    if (article != null && mounted) {
      setState(() {
        _nomCtrl.text = article.nom;
        _refCtrl.text = article.ref;
        _descCtrl.text = article.description;
        _categorie = article.categorie.trim().isNotEmpty
            ? article.categorie.trim()
            : categories.first;
        _unite = article.unite.isNotEmpty && unites.contains(article.unite)
            ? article.unite
            : unites.first;
        _prixAchatCtrl.text = article.prixAchat > 0 ? article.prixAchat.toString() : '';
        _prixVenteCtrl.text = article.prixVente > 0 ? article.prixVente.toString() : '';
        _stockCtrl.text = article.stock.toString();
        _stockMinCtrl.text = article.stockMin.toString();
        _fournisseurCtrl.text = article.fournisseur;
        _longueurCtrl.text = article.longueur?.toString() ?? '';
        _epaisseurCtrl.text =
            article.epaisseur > 0 ? article.epaisseur.toString() : '';
        _provenance = article.provenance.isNotEmpty && provenances.contains(article.provenance)
            ? article.provenance
            : provenances.first;
        _photoBase64 = article.photo.isNotEmpty ? article.photo : null;
      });
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _refCtrl.dispose();
    _descCtrl.dispose();
    _prixAchatCtrl.dispose();
    _prixVenteCtrl.dispose();
    _stockCtrl.dispose();
    _stockMinCtrl.dispose();
    _fournisseurCtrl.dispose();
    _longueurCtrl.dispose();
    _epaisseurCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: source, imageQuality: 70, maxWidth: 800);
      if (picked != null) {
        final bytes = await File(picked.path).readAsBytes();
        if (!mounted) return;
        setState(() {
          _photoBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de charger l\'image: $e')),
      );
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        final metier = ctx.metier;

        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: Rayon.feuille,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PoigneeFeuille(),

              // En-tête Photo Banner Card (Style VenteDetailSheet)
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
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Rayon.md),
                        ),
                        child: Icon(
                          Icons.add_a_photo_rounded,
                          size: 26,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Photo de l\'article',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            BadgePastille(
                              texte: _photoBase64 != null
                                  ? 'Photo choisie'
                                  : 'Illustration catalogue',
                              couleur: _photoBase64 != null
                                  ? metier.succes
                                  : scheme.primary,
                              icone: _photoBase64 != null
                                  ? Icons.check_circle_rounded
                                  : Icons.image_rounded,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Espace.md),

              // Options de Sélection
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                child: AppCard(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rayon.lg)),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _pickImage(ImageSource.camera);
                          },
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(Rayon.lg)),
                          child: Padding(
                            padding: const EdgeInsets.all(Espace.md),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(Rayon.sm),
                                  ),
                                  child: Icon(Icons.camera_alt_rounded,
                                      color: scheme.primary, size: 20),
                                ),
                                const SizedBox(width: Espace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Prendre une photo',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Utiliser l\'appareil photo',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded,
                                    size: 18, color: scheme.outline),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Material(
                        color: Colors.transparent,
                        borderRadius: _photoBase64 == null
                            ? const BorderRadius.vertical(bottom: Radius.circular(Rayon.lg))
                            : BorderRadius.zero,
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _pickImage(ImageSource.gallery);
                          },
                          borderRadius: _photoBase64 == null
                              ? const BorderRadius.vertical(bottom: Radius.circular(Rayon.lg))
                              : BorderRadius.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(Espace.md),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: metier.info.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(Rayon.sm),
                                  ),
                                  child: Icon(Icons.photo_library_rounded,
                                      color: metier.info, size: 20),
                                ),
                                const SizedBox(width: Espace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Choisir dans la galerie',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Importer une image existante',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded,
                                    size: 18, color: scheme.outline),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_photoBase64 != null) ...[
                        const Divider(height: 1),
                        Material(
                          color: Colors.transparent,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Rayon.lg)),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() => _photoBase64 = null);
                            },
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Rayon.lg)),
                            child: Padding(
                              padding: const EdgeInsets.all(Espace.md),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: metier.danger.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(Rayon.sm),
                                    ),
                                    child: Icon(Icons.delete_outline_rounded,
                                        color: metier.danger, size: 20),
                                  ),
                                  const SizedBox(width: Espace.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Supprimer la photo',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: metier.danger,
                                          ),
                                        ),
                                        Text(
                                          'Retirer l\'image du produit',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 18, color: metier.danger),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Espace.md),

              // Bouton Annuler Orange
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(Espace.page),
                  child: AppButton(
                    label: 'Annuler',
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(ctx),
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

  /// Inscrit le stock de départ au journal des mouvements.
  ///
  /// C'est ce qui manquait : le stock initial était posé directement dans la
  /// fiche, et l'historique de l'article restait vide alors qu'il y avait
  /// cinquante barres en dépôt. Plus personne ne pouvait dire d'où elles
  /// venaient, ni depuis quand elles étaient là.
  ///
  /// Le type du mouvement dit l'origine, et il n'est pas décoratif :
  ///
  ///   — « ajustement » pour une reprise d'inventaire. Le serveur l'applique en
  ///     ABSOLU : la quantité saisie devient le stock, quoi qu'il y ait eu
  ///     avant. C'est exactement le sens d'un solde d'ouverture, et cela rend
  ///     l'opération rejouable sans risque.
  ///   — « entrée » pour une livraison. Le serveur l'applique en ÉCART : elle
  ///     s'ajoute au stock, et elle entre dans l'historique du fournisseur.
  ///
  /// Aucune dépense n'est créée dans un cas comme dans l'autre. Le stock et
  /// l'argent sont deux registres distincts dans toute l'application : une
  /// livraison peut être payée d'avance, à trente jours, ou jamais. C'est dit à
  /// l'écran plutôt que deviné ici.
  Future<void> _enregistrerStockOuverture({
    required Stores stores,
    required OpQueue opQueue,
    required Article article,
    required int quantite,
  }) async {
    final livraison = _origineStock == OrigineStock.livraisonFournisseur &&
        _fournisseurLivraison != null;
    final f = _fournisseurLivraison;

    final mouvement = MouvementStock(
      id: const Uuid().v4(),
      articleId: article.id,
      type: livraison ? 'entrée' : 'ajustement',
      quantite: quantite,
      quantiteAvant: 0,
      quantiteApres: quantite,
      date: DateTime.now().toIso8601String(),
      utilisateur: ref.read(utilisateurActuelProvider)?.nom ?? 'Utilisateur',
      note: livraison
          ? 'Première livraison à la création de l\'article'
          : 'Stock déjà en magasin à la création de l\'article',
      // Le nom est recopié en plus de l'identifiant : un fournisseur renommé ou
      // supprimé ne doit pas effacer la trace de ce qui a été pris chez lui.
      fournisseurId: livraison ? f!.id : null,
      fournisseurNom: livraison ? f!.nom : null,
      fournisseurQuartier:
          livraison && f!.quartier.isNotEmpty ? f.quartier : null,
    );

    await stores.upsert('mouvement', mouvement);
    // Le stock local prend sa valeur d'ouverture tout de suite : l'application
    // sert d'abord hors ligne, et un article créé avec cinquante barres qui en
    // affiche zéro serait recréé.
    await stores.upsert('article', article.copyWith(stock: quantite));
    await opQueue.enqueue('mouvement', {'mouvement': mouvement.toJson()});
  }

  Future<void> _choisirFournisseurLivraison() async {
    final choisi = await choisirFournisseur(context);
    if (!mounted || choisi == null) return;
    setState(() {
      _fournisseurLivraison = choisi;
      _origineStock = OrigineStock.livraisonFournisseur;
      // Le fournisseur habituel de la fiche suit celui de la première
      // livraison, s'il n'a pas été renseigné à la main : c'est ce que
      // l'utilisateur veut dire dans quasiment tous les cas, et il reste
      // modifiable juste en dessous.
      if (_fournisseurCtrl.text.trim().isEmpty) {
        _fournisseurCtrl.text = choisi.nom;
      }
    });
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;

    final stockSaisi = parseMontantClean(_stockCtrl.text);

    // Une livraison sans fournisseur nommé n'est pas une livraison : on refuse
    // avant d'écrire, plutôt que d'enregistrer un mouvement orphelin qui ne
    // remonterait dans l'historique d'aucun fournisseur.
    if (_editId == null &&
        stockSaisi > 0 &&
        _origineStock == OrigineStock.livraisonFournisseur &&
        _fournisseurLivraison == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Indiquez chez quel fournisseur cette marchandise '
            'a été prise, ou choisissez « Déjà en magasin ».'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    // Vendre sous le prix d'achat n'est pas interdit — une liquidation se
    // décide —, mais ça ne se fait pas par une faute de frappe. On demande.
    final prixAchat = parseMontantClean(_prixAchatCtrl.text);
    final prixVente = parseMontantClean(_prixVenteCtrl.text);
    if (prixAchat > 0 && prixVente < prixAchat) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vente à perte ?'),
          content: Text(
              'Le prix de vente (${fmtGNF(prixVente)}) est inférieur au prix '
              'd\'achat (${fmtGNF(prixAchat)}). Chaque vente de cet article '
              'fera perdre ${fmtGNF(prixAchat - prixVente)}.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Corriger')),
            AppButton(
                label: 'Enregistrer quand même',
                onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _isLoading = true);

    final creation = _editId == null;
    final existant = creation ? null : await ref.read(storesProvider).getArticle(_editId!);

    final article = Article(
      id: _editId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nom: _nomCtrl.text.trim(),
      ref: _refCtrl.text.trim(),
      categorie: _categorie,
      description: _descCtrl.text.trim(),
      unite: _unite,
      prixAchat: parseMontantClean(_prixAchatCtrl.text),
      prixVente: parseMontantClean(_prixVenteCtrl.text),
      // À la CRÉATION, l'article naît à zéro : c'est le mouvement d'ouverture
      // ci-dessous qui pose le stock, pour qu'il en reste une trace datée et
      // attribuée. Écrire la quantité ici ET envoyer le mouvement la compterait
      // deux fois — le serveur applique le mouvement par-dessus la fiche.
      //
      // En MODIFICATION, on reprend le stock enregistré sans y toucher : le
      // champ est désactivé, et reprendre la valeur qu'avait le formulaire à son
      // ouverture écraserait les ventes survenues pendant la saisie.
      stock: creation ? 0 : (existant?.stock ?? 0),
      stockMin: parseMontantClean(_stockMinCtrl.text),
      fournisseur: _fournisseurCtrl.text.trim(),
      photo: _photoBase64 ?? '',
      longueur: double.tryParse(_longueurCtrl.text),
      epaisseur: double.tryParse(_epaisseurCtrl.text) ?? 0,
      provenance: _provenance,
    );

    try {
      final stores = ref.read(storesProvider);
      final opQueue = ref.read(opQueueProvider);
      final baseRev = existant?.rev;

      await stores.upsert('article', article);
      await opQueue.enqueue('article', {
        'record': article.toJson(),
        if (baseRev != null) 'baseRev': baseRev,
      });

      // Le stock d'ouverture, s'il y en a un.
      //
      // Déposé APRÈS l'article, et jamais avant : le serveur refuse un
      // mouvement sur un article qu'il ne connaît pas encore, et la file part
      // dans l'ordre de dépôt.
      if (creation && stockSaisi > 0) {
        await _enregistrerStockOuverture(
          stores: stores,
          opQueue: opQueue,
          article: article,
          quantite: stockSaisi,
        );
      }

      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _afficherDialogNouvelleCategorie() async {
    final ctrl = TextEditingController();
    final nouvelleCat = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.category_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Nouvelle catégorie'),
            ],
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nom de la catégorie',
              hintText: 'Ex: Accessoires, Visserie, Peinture...',
              prefixIcon: Icon(Icons.label_rounded),
            ),
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) {
                Navigator.of(ctx).pop(val.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  Navigator.of(ctx).pop(ctrl.text.trim());
                }
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Ajouter'),
            ),
          ],
        );
      },
    );

    if (nouvelleCat != null && nouvelleCat.trim().isNotEmpty) {
      final catClean = nouvelleCat.trim();
      setState(() {
        if (!_customCategories.contains(catClean)) {
          _customCategories.add(catClean);
        }
        _categorie = catClean;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Catégorie "$catClean" ajoutée et sélectionnée'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEdit = _editId != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Modifier l\'article' : 'Nouveau Produit',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              isEdit ? 'Mise à jour de la fiche stock' : 'Création dans le catalogue',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_photoBase64 != null)
            IconButton(
              tooltip: 'Changer la photo',
              icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: _showImageOptions,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Espace.page,
            Espace.sm,
            Espace.page,
            Espace.basDeListe,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Photo Header Card
              _buildPhotoCard(theme, scheme),
              const SizedBox(height: Espace.lg),

              // Section 1: Informations Générales
              const SectionHeader(
                titre: 'Informations Générales',
                icone: Icons.inventory_2_rounded,
              ),
              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nomCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nom de l\'article *',
                        hintText: 'Ex: Tube carré 40x40x2',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                      validator: (v) => v!.trim().isEmpty ? 'Le nom est requis' : null,
                    ),
                    const SizedBox(height: Espace.md),
                    TextFormField(
                      controller: _refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Référence / Code SKU',
                        hintText: 'Ex: REF-40402',
                        prefixIcon: Icon(Icons.qr_code_rounded),
                      ),
                    ),
                    const SizedBox(height: Espace.md),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_categorie),
                            initialValue:
                                _categoriesDisponibles.contains(_categorie)
                                    ? _categorie
                                    : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Catégorie de produit *',
                              prefixIcon: Icon(Icons.category_rounded),
                            ),
                            borderRadius: BorderRadius.circular(Rayon.md),
                            items: [
                              ..._categoriesDisponibles.map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DropdownMenuItem<String>(
                                value: '__NOUVELLE_CATEGORIE__',
                                child: Row(
                                  children: [
                                    Icon(Icons.add_rounded,
                                        size: 18, color: scheme.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '+ Autre / Nouvelle catégorie...',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v == '__NOUVELLE_CATEGORIE__') {
                                _afficherDialogNouvelleCategorie();
                              } else if (v != null) {
                                setState(() => _categorie = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: Espace.xs),
                        IconButton.filledTonal(
                          tooltip: 'Saisir une nouvelle catégorie',
                          icon: const Icon(Icons.add_rounded),
                          onPressed: _afficherDialogNouvelleCategorie,
                        ),
                      ],
                    ),
                    const SizedBox(height: Espace.md),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description complémentaire',
                        hintText: 'Spécifications particulières, alliage...',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.xl),

              // Section 2: Tarification & Unités
              const SectionHeader(
                titre: 'Tarification & Unités',
                icone: Icons.payments_rounded,
              ),
              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unité de mesure',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Espace.xs),
                    Wrap(
                      spacing: Espace.sm,
                      children: unites.map((u) {
                        final selected = _unite == u;
                        return ChoiceChip(
                          label: Text(u),
                          selected: selected,
                          onSelected: (val) {
                            if (val) setState(() => _unite = u);
                          },
                          avatar: Icon(
                            u == 'Barre'
                                ? Icons.straighten_rounded
                                : u == 'Plaque'
                                    ? Icons.layers_rounded
                                    : Icons.description_rounded,
                            size: 16,
                            color: selected ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: Espace.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _prixVenteCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Prix vente *',
                              suffixText: 'GNF',
                              prefixIcon: Icon(Icons.sell_rounded),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Requis';
                              final val = parseMontantClean(v);
                              if (val <= 0) return '> 0';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: Espace.md),
                        Expanded(
                          child: TextFormField(
                            controller: _prixAchatCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Prix d\'achat',
                              suffixText: 'GNF',
                              prefixIcon: Icon(Icons.shopping_bag_rounded),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              if (parseMontantClean(v) < 0) return '≥ 0';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.xl),

              // Section 3: Gestion des Stocks
              const SectionHeader(
                titre: 'Gestion des Stocks',
                icone: Icons.warehouse_rounded,
              ),
              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number,
                        // Le stock ne se modifie plus par ce formulaire une
                        // fois l'article créé : il se corrige par un
                        // ajustement d'inventaire, qui laisse une trace et un
                        // motif. Le laisser modifiable ici écrasait en silence
                        // les entrées et les ventes survenues entre-temps.
                        enabled: _editId == null,
                        decoration: InputDecoration(
                          labelText: 'Stock Initial',
                          helperText: _editId == null
                              ? null
                              : 'Se corrige par « Ajuster » sur la fiche',
                          prefixIcon: const Icon(Icons.inventory_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: TextFormField(
                        controller: _stockMinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Stock Minimum',
                          helperText: 'Alerte de réappro',
                          prefixIcon: Icon(Icons.warning_amber_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // La question ne se pose qu'à la création, et seulement s'il y a
              // effectivement de la marchandise à expliquer.
              if (_editId == null && _stockInitial > 0) ...[
                const SizedBox(height: Espace.md),
                _CarteOrigineStock(
                  quantite: _stockInitial,
                  unite: _unite,
                  origine: _origineStock,
                  fournisseur: _fournisseurLivraison,
                  onOrigine: (o) => setState(() {
                    _origineStock = o;
                    if (o == OrigineStock.dejaEnMagasin) {
                      _fournisseurLivraison = null;
                    }
                  }),
                  onChoisirFournisseur: _choisirFournisseurLivraison,
                ),
              ],
              const SizedBox(height: Espace.xl),

              // Section 4: Caractéristiques & Source
              const SectionHeader(
                titre: 'Caractéristiques & Provenance',
                icone: Icons.tune_rounded,
              ),
              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _longueurCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Longueur',
                              suffixText: 'm',
                              prefixIcon: Icon(Icons.height_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: Espace.md),
                        Expanded(
                          child: TextFormField(
                            controller: _epaisseurCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Épaisseur',
                              suffixText: 'mm',
                              prefixIcon: Icon(Icons.line_weight_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Espace.md),
                    Text(
                      'Pays de provenance',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Espace.xs),
                    Wrap(
                      spacing: Espace.sm,
                      runSpacing: 4,
                      children: provenances.map((p) {
                        final selected = _provenance == p;
                        return ChoiceChip(
                          label: Text(p),
                          selected: selected,
                          onSelected: (val) {
                            if (val) setState(() => _provenance = p);
                          },
                          avatar: Icon(
                            Icons.public_rounded,
                            size: 16,
                            color: selected ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: Espace.md),
                    TextFormField(
                      controller: _fournisseurCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fournisseur principal',
                        hintText: 'Nom de la société / Usine',
                        prefixIcon: Icon(Icons.business_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(Espace.page),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: AppButton(
            label: _isLoading
                ? 'Enregistrement en cours…'
                : (isEdit ? 'Mettre à jour l\'article' : 'Enregistrer l\'article'),
            icon: isEdit ? Icons.save_rounded : Icons.check_circle_rounded,
            loading: _isLoading,
            onPressed: _isLoading ? null : _enregistrer,
            expanded: true,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCard(ThemeData theme, ColorScheme scheme) {
    if (_photoBase64 != null) {
      return Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rayon.carte.topLeft.x),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: Rayon.carte,
          child: Stack(
            fit: StackFit.expand,
            children: [
              bytesFromBase64(_photoBase64) != null
                  ? Image.memory(
                      bytesFromBase64(_photoBase64)!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHigh,
                        child: const Center(child: Icon(Icons.broken_image_rounded, size: 48)),
                      ),
                    )
                  : Container(
                      color: scheme.surfaceContainerHigh,
                      child: const Center(child: Icon(Icons.broken_image_rounded, size: 48)),
                    ),
              // Gradient Overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: Espace.md,
                left: Espace.md,
                right: Espace.md,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(Rayon.sm),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Photo attachée',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showImageOptions,
                      icon: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                      label: const Text('Changer', style: TextStyle(color: Colors.white, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(horizontal: Espace.md),
                        minimumSize: const Size(0, 36),
                        backgroundColor: Colors.black.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showImageOptions,
        borderRadius: Rayon.carte,
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(Espace.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: Rayon.carte,
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(Espace.md),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_a_photo_rounded,
                  size: 32,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: Espace.sm),
              Text(
                'Ajouter une photo de l\'article',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Prendre avec la caméra ou choisir dans la galerie',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « D'où vient ce stock ? » — posée seulement à la création, et seulement s'il
/// y a de la marchandise à expliquer.
///
/// La distinction n'est pas administrative. Une reprise d'inventaire est de la
/// marchandise déjà payée, parfois depuis des mois : l'attribuer à un
/// fournisseur inventerait un historique d'achat, et gonflerait ses statistiques
/// de choses qu'il n'a jamais livrées. Une livraison, elle, appartient à
/// quelqu'un — et le magasin lui doit peut-être encore de l'argent.
class _CarteOrigineStock extends StatelessWidget {
  const _CarteOrigineStock({
    required this.quantite,
    required this.unite,
    required this.origine,
    required this.fournisseur,
    required this.onOrigine,
    required this.onChoisirFournisseur,
  });

  final int quantite;
  final String unite;
  final OrigineStock origine;
  final Fournisseur? fournisseur;
  final ValueChanged<OrigineStock> onOrigine;
  final VoidCallback onChoisirFournisseur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;
    final livraison = origine == OrigineStock.livraisonFournisseur;

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: Espace.xs + 2),
              Expanded(
                child: Text(
                  "D'où viennent ces ${fmtNombre(quantite)} $unite ?",
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.sm),

          RadioGroup<OrigineStock>(
            groupValue: origine,
            onChanged: (v) => v == null ? null : onOrigine(v),
            child: Column(
              children: [
                RadioListTile<OrigineStock>(
                  value: OrigineStock.dejaEnMagasin,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: const Text('Déjà en magasin'),
                  subtitle: Text(
                    'Marchandise présente avant, déjà payée. '
                    'Enregistrée comme reprise d\'inventaire.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                RadioListTile<OrigineStock>(
                  value: OrigineStock.livraisonFournisseur,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: const Text("Livraison d'un fournisseur"),
                  subtitle: Text(
                    "Entre dans l'historique du fournisseur.",
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),

          if (livraison) ...[
            const SizedBox(height: Espace.xs),
            InkWell(
              onTap: onChoisirFournisseur,
              borderRadius: BorderRadius.circular(Rayon.md),
              child: Container(
                padding: const EdgeInsets.all(Espace.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(Rayon.md),
                  border: Border.all(
                    color: fournisseur == null
                        ? metier.alerte.withValues(alpha: 0.6)
                        : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      fournisseur == null
                          ? Icons.error_outline_rounded
                          : Icons.handshake_rounded,
                      color: fournisseur == null ? metier.alerte : scheme.primary,
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fournisseur?.nom ?? 'Choisir le fournisseur',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: fournisseur == null
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                            ),
                          ),
                          if (fournisseur != null)
                            Text(
                              [fournisseur!.telephone, fournisseur!.quartier]
                                  .where((x) => x.isNotEmpty)
                                  .join(' · '),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: Espace.sm),
          // Le stock et l'argent sont deux registres distincts dans toute
          // l'application. Le dire ici évite la question qui vient toujours
          // après : « pourquoi ma caisse n'a pas bougé ? »
          Text(
            livraison
                ? "Aucune dépense n'est créée. Si ce fournisseur doit être payé, "
                    'saisissez-la depuis Dépenses.'
                : "Aucune dépense n'est créée : cette marchandise est réputée "
                    'déjà payée.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
