import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/sync/op_queue.dart';
import '../../core/db/stores.dart';
import '../dashboard/dashboard_page.dart';
import '../fournisseurs/fournisseur_form_sheet.dart';

/// Cette feuille n'enregistre que des entrées de marchandise. Écrit une fois,
/// ici, plutôt qu'en dur à trois endroits du fichier — dont l'un servait à
/// afficher le stock prévu et un autre à l'enregistrer.
const String _kTypeMouvement = 'entrée';

final fournisseursMouvementProvider = StreamProvider.autoDispose<List<Fournisseur>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchFournisseurs();
});

/// Saisie d'une entrée de marchandise chez un fournisseur.
///
/// La feuille portait auparavant les trois natures de mouvement (entrée,
/// sortie, ajustement) ; elle est désormais dédiée à l'achat fournisseur. Le
/// paramètre `typePreChoisi` qui la pilotait a été RETIRÉ plutôt que laissé en
/// place : le corps de la méthode l'ignorait déjà et écrivait « entrée » en
/// dur, si bien qu'un appel avec « sortie » aurait enregistré une entrée — un
/// paramètre qui ne fait rien est un piège tendu au prochain appelant.
class MouvementSheet extends ConsumerStatefulWidget {
  final Article article;

  const MouvementSheet({
    super.key,
    required this.article,
  });

  @override
  ConsumerState<MouvementSheet> createState() => _MouvementSheetState();
}

class _MouvementSheetState extends ConsumerState<MouvementSheet> {
  late TextEditingController _quantiteCtrl, _noteCtrl, _quartierCtrl;
  int _quantite = 0;
  bool _isSubmitting = false;
  Fournisseur? _fournisseurChoisi;

  @override
  void initState() {
    super.initState();
    // Force to 'entrée' as we repurpose this sheet for "Achat Fournisseur"
    _quantiteCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _quartierCtrl = TextEditingController();
    _quantiteCtrl.addListener(() {
      final val = parseMontantClean(_quantiteCtrl.text);
      if (val != _quantite) {
        setState(() => _quantite = val);
      }
    });
  }

  @override
  void dispose() {
    _quantiteCtrl.dispose();
    _noteCtrl.dispose();
    _quartierCtrl.dispose();
    super.dispose();
  }

  void _ajouterQuantite(int delta) {
    final actuel = parseMontantClean(_quantiteCtrl.text);
    final nouveau = (actuel + delta).clamp(0, 999999);
    _quantiteCtrl.text = nouveau.toString();
    _quantiteCtrl.selection = TextSelection.collapsed(offset: _quantiteCtrl.text.length);
  }

  /// Le stock annoncé à l'écran passe par la même règle que l'écriture, et que
  /// celle du serveur : trois additions écrites séparément finissent par dire
  /// trois choses différentes.
  int _stockApres() =>
      stockApresMouvement(widget.article.stock, _kTypeMouvement, _quantite);

  Future<void> _valider() async {
    final quantite = parseMontantClean(_quantiteCtrl.text);
    if (quantite <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Veuillez saisir une quantité supérieure à 0'),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    
    if (_fournisseurChoisi == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Veuillez sélectionner un fournisseur'),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final mouvement = MouvementStock(
      id: const Uuid().v4(),
      articleId: widget.article.id,
      type: _kTypeMouvement,
      quantite: quantite,
      // Avant/après tels que ce téléphone les connaît : le serveur les
      // recalculera sur son propre stock, mais le journal local les montre
      // tout de suite.
      quantiteAvant: widget.article.stock,
      quantiteApres:
          stockApresMouvement(widget.article.stock, _kTypeMouvement, quantite),
      date: DateTime.now().toIso8601String(),
      utilisateur: ref.read(utilisateurActuelProvider)?.nom ?? 'Utilisateur',
      note: _noteCtrl.text.trim(),
      fournisseurId: _fournisseurChoisi?.id,
      fournisseurNom: _fournisseurChoisi?.nom,
      fournisseurQuartier: _fournisseurChoisi != null && _quartierCtrl.text.trim().isNotEmpty
          ? _quartierCtrl.text.trim()
          : null,
    );

    try {
      final stores = ref.read(storesProvider);
      final opQueue = ref.read(opQueueProvider);

      // Écriture locale AVANT l'envoi : l'application sert d'abord hors ligne.
      // Seule la file était alimentée jusqu'ici, si bien qu'une entrée saisie
      // sans réseau ne bougeait pas le stock à l'écran — le magasin voyait
      // toujours zéro barre après en avoir reçu cinquante, les ressaisissait,
      // et le serveur en comptait cent au retour de la connexion. Le stock du
      // serveur reste celui qui fait foi : il écrasera celui-ci au prochain
      // instantané.
      //
      // Mouvement et stock dans UNE transaction : tout passe, ou rien.
      await stores.transaction(() async {
        await stores.upsert('mouvement', mouvement);
        final frais = await stores.getArticle(widget.article.id);
        if (frais != null) {
          await stores.upsert(
            'article',
            frais.copyWith(
              stock: stockApresMouvement(
                  frais.stock, mouvement.type, mouvement.quantite),
            ),
          );
        }
      });

      await opQueue.enqueue('mouvement', {'mouvement': mouvement.toJson()});
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _choisirFournisseur(List<Fournisseur> fournisseurs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: Rayon.feuille,
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            children: [
              const PoigneeFeuille(),
              Padding(
                padding: const EdgeInsets.all(Espace.md),
                child: Text(
                  'Sélectionner un fournisseur',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: ListView.separated(
                    itemCount: fournisseurs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final f = fournisseurs[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          child: Text(
                            f.nom.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(f.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: f.telephone.isNotEmpty ? Text(f.telephone) : null,
                        onTap: () {
                          setState(() => _fournisseurChoisi = f);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = context.metier.succes;
    final stockFinal = _stockApres();
    
    final fournisseursAsync = ref.watch(fournisseursMouvementProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + Espace.lg,
        left: Espace.page,
        right: Espace.page,
        top: Espace.sm,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PoigneeFeuille(),
            const SizedBox(height: Espace.xs),

            // En-tête : Achat Fournisseur
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add_business_rounded, color: typeColor),
                ),
                const SizedBox(width: Espace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Achat Fournisseur',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      BadgePastille(
                        texte: widget.article.nom,
                        couleur: scheme.primary,
                        icone: Icons.inventory_2_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espace.lg),
            
            // Sélection du fournisseur
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fournisseur *',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const FournisseurFormSheet(),
                    );
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Nouveau'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espace.xs + 2),
            fournisseursAsync.when(
              data: (fournisseurs) {
                return InkWell(
                  onTap: () => _choisirFournisseur(fournisseurs),
                  borderRadius: BorderRadius.circular(Rayon.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Espace.md, vertical: Espace.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(Rayon.md),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.business_rounded,
                            size: 20,
                            color: _fournisseurChoisi != null ? scheme.primary : scheme.outline,
                          ),
                        ),
                        const SizedBox(width: Espace.md),
                        Expanded(
                          child: Text(
                            _fournisseurChoisi?.nom ?? 'Sélectionner un fournisseur...',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: _fournisseurChoisi != null ? scheme.onSurface : scheme.onSurfaceVariant,
                              fontWeight: _fournisseurChoisi != null ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        Icon(Icons.unfold_more_rounded, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erreur: $e'),
            ),
            if (_fournisseurChoisi != null && _fournisseurChoisi!.telephone.isNotEmpty) ...[
              const SizedBox(height: Espace.xs),
              AppCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(horizontal: Espace.md, vertical: Espace.sm),
                child: Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      _fournisseurChoisi!.telephone,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_fournisseurChoisi!.quartier.isNotEmpty) ...[
                      const SizedBox(width: Espace.sm),
                      Text('•', style: TextStyle(color: scheme.outline)),
                      const SizedBox(width: Espace.sm),
                      Expanded(
                        child: Text(
                          _fournisseurChoisi!.quartier,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: Espace.lg),

            // Saisie Quantité
            Text(
              'Quantité achetée *',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: Espace.sm),
            TextFormField(
              controller: _quantiteCtrl,
              keyboardType: TextInputType.number,
              autofocus: _fournisseurChoisi != null,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: typeColor,
              ),
              decoration: InputDecoration(
                labelText: 'Quantité (+)',
                suffixText: widget.article.unite,
                prefixIcon: Icon(Icons.numbers_rounded, color: typeColor),
              ),
            ),
            const SizedBox(height: Espace.sm),

            // Raccourcis +
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [1, 5, 10, 50, 100].map((val) {
                  return Padding(
                    padding: const EdgeInsets.only(right: Espace.xs),
                    child: ActionChip(
                      label: Text('+$val', style: const TextStyle(fontWeight: FontWeight.bold)),
                      backgroundColor: typeColor.withValues(alpha: 0.1),
                      side: BorderSide(color: typeColor.withValues(alpha: 0.2)),
                      onPressed: () => _ajouterQuantite(val),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: Espace.md),
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (optionnel)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (_fournisseurChoisi != null) ...[
              const SizedBox(height: Espace.md),
              TextFormField(
                controller: _quartierCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quartier / Lieu (optionnel)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
            ],
            const SizedBox(height: Espace.xl),

            // Aperçu Stock
            Container(
              padding: const EdgeInsets.all(Espace.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(Rayon.md),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Nouveau stock',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: Espace.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.article.stock}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: Espace.xs),
                      const Icon(Icons.arrow_right_alt_rounded, size: 16),
                      const SizedBox(width: Espace.xs),
                      Text(
                        '$stockFinal ${widget.article.unite}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: typeColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                      ),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: Espace.md),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _valider,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: typeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Valider l\'achat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
