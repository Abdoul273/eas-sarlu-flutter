import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/db/stores.dart';
import '../../core/sync/op_queue.dart';

class ArticleFormPage extends ConsumerStatefulWidget {
  const ArticleFormPage({super.key});

  @override
  ConsumerState<ArticleFormPage> createState() => _ArticleFormPageState();
}

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
        _categorie = article.categorie.isNotEmpty && categories.contains(article.categorie)
            ? article.categorie
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

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final article = Article(
      id: _editId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nom: _nomCtrl.text.trim(),
      ref: _refCtrl.text.trim(),
      categorie: _categorie,
      description: _descCtrl.text.trim(),
      unite: _unite,
      prixAchat: parseMontantClean(_prixAchatCtrl.text),
      prixVente: parseMontantClean(_prixVenteCtrl.text),
      stock: parseMontantClean(_stockCtrl.text),
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
      final baseRev =
          _editId != null ? (await stores.getArticle(_editId!))?.rev : null;

      await stores.upsert('article', article);

      final payload = <String, dynamic>{
        'record': article.toJson(),
        if (baseRev != null) 'baseRev': baseRev,
      };
      await opQueue.enqueue('article', payload);

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
                    DropdownButtonFormField<String>(
                      initialValue: _categorie,
                      decoration: const InputDecoration(
                        labelText: 'Catégorie de produit',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                      borderRadius: BorderRadius.circular(Rayon.md),
                      items: categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _categorie = v);
                      },
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
                        decoration: const InputDecoration(
                          labelText: 'Stock Initial',
                          prefixIcon: Icon(Icons.inventory_rounded),
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
