import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../../core/sync/op_queue.dart';
import '../dashboard/dashboard_page.dart';

// ─── Ajustement d'inventaire ──────────────────────────────────────────────────
//
// Le seul moyen de remettre un stock d'aplomb quand il ne correspond plus à ce
// qu'il y a réellement en dépôt : erreur de saisie, casse, vol, comptage annuel.
//
// La fiche article a perdu ses boutons « Sortie » et « Ajuster » au profit de
// « Achat Fournisseur » et « Vente ». Le raisonnement se tient — le stock ne
// devrait bouger que par un achat ou une vente — mais il ne laissait plus
// AUCUNE issue : une quantité tapée à 500 au lieu de 50 restait fausse pour
// toujours, et faussait avec elle la valeur du stock, les alertes de
// réapprovisionnement et le coût des marchandises vendues.
//
// Deux partis pris distinguent cette feuille de celle des achats :
//
//   1. On saisit le stock RÉELLEMENT COMPTÉ, pas un écart. Personne ne compte
//      « moins quatre-cent-cinquante barres » : on compte ce qu'il y a, et
//      l'écart se déduit. C'est aussi ce qu'attend le serveur, qui traite
//      l'ajustement en mode « absolu ».
//   2. Le motif est OBLIGATOIRE. Un mouvement qui n'est ni un achat ni une
//      vente doit s'expliquer, sinon le journal d'activité ne sert plus à rien
//      le jour où l'on cherche pourquoi il manque trente barres.

/// Motifs proposés. Une liste courte, tirée de ce qui arrive vraiment au
/// comptoir — un champ libre seul finit rempli de « correction ».
const List<String> kMotifsAjustement = [
  'Comptage / inventaire',
  'Erreur de saisie',
  'Casse ou détérioration',
  'Perte ou vol',
  'Retour fournisseur',
];

class AjustementSheet extends ConsumerStatefulWidget {
  final Article article;

  const AjustementSheet({super.key, required this.article});

  @override
  ConsumerState<AjustementSheet> createState() => _AjustementSheetState();
}

class _AjustementSheetState extends ConsumerState<AjustementSheet> {
  late final TextEditingController _compteCtrl;
  late final TextEditingController _detailCtrl;
  String? _motif;
  int _compte = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pré-rempli au stock enregistré : l'utilisateur corrige ce qu'il voit au
    // lieu de tout retaper, et un champ laissé tel quel ne change rien.
    _compte = widget.article.stock;
    _compteCtrl = TextEditingController(text: '${widget.article.stock}');
    _detailCtrl = TextEditingController();
    _compteCtrl.addListener(() {
      final val = parseMontantClean(_compteCtrl.text);
      if (val != _compte) setState(() => _compte = val);
    });
  }

  @override
  void dispose() {
    _compteCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  /// Écart entre ce qui est compté et ce qui est enregistré.
  int get _ecart => _compte - widget.article.stock;

  void _avertir(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<void> _valider() async {
    if (_isSubmitting) return;

    // L'écart d'abord, le motif ensuite : réclamer une justification pour une
    // correction qui n'en est pas une envoie chercher au mauvais endroit.
    if (_ecart == 0) {
      // Enregistrer un mouvement qui ne change rien encombre le journal et fait
      // croire à une correction qui n'a pas eu lieu.
      _avertir('Le stock compté est déjà celui enregistré : rien à corriger');
      return;
    }
    if (_motif == null) {
      _avertir('Indiquez pourquoi le stock est corrigé');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final stores = ref.read(storesProvider);
      final opQueue = ref.read(opQueueProvider);

      final detail = _detailCtrl.text.trim();
      final mouvement = MouvementStock(
        id: const Uuid().v4(),
        articleId: widget.article.id,
        type: 'ajustement',
        // La quantité d'un ajustement est le stock VOULU, pas l'écart : c'est
        // ainsi que le serveur la lit (mode « absolu »), et c'est ce que
        // `stockApresMouvement` applique de son côté.
        quantite: _compte,
        quantiteAvant: widget.article.stock,
        quantiteApres: _compte,
        date: DateTime.now().toIso8601String(),
        utilisateur: ref.read(utilisateurActuelProvider)?.nom ?? 'Utilisateur',
        note: detail.isEmpty ? _motif! : '$_motif — $detail',
      );

      // Écriture locale d'abord, comme pour un achat : l'application sert hors
      // ligne, et un stock corrigé qui ne bouge pas à l'écran serait recorrigé.
      //
      // Mouvement et stock dans UNE transaction : un mouvement enregistré
      // sans son effet sur l'article ferait mentir le journal.
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
      _avertir('Ajustement non enregistré : $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;

    final ecart = _ecart;
    final couleurEcart = ecart == 0
        ? scheme.onSurfaceVariant
        : (ecart > 0 ? metier.succes : metier.danger);

    return Padding(
      padding: EdgeInsets.only(
        left: Espace.page,
        right: Espace.page,
        top: Espace.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + Espace.page,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PoigneeFeuille(),
            const SizedBox(height: Espace.xs),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.tune_rounded, color: scheme.primary),
                ),
                const SizedBox(width: Espace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Ajustement d'inventaire",
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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

            // Ce que dit l'application, avant correction.
            AppCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(
                  horizontal: Espace.md, vertical: Espace.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Stock enregistré', style: theme.textTheme.bodyMedium),
                  Text(
                    '${fmtNombre(widget.article.stock)} ${widget.article.unite}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            Text(
              'Stock réellement compté *',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: Espace.sm),
            TextFormField(
              controller: _compteCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
              decoration: InputDecoration(
                labelText: 'Ce qu\'il y a en dépôt',
                suffixText: widget.article.unite,
                prefixIcon:
                    Icon(Icons.inventory_rounded, color: scheme.primary),
              ),
            ),
            const SizedBox(height: Espace.md),

            Text(
              'Motif *',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Espace.xs + 2),
            Wrap(
              spacing: Espace.xs,
              runSpacing: Espace.xs,
              children: kMotifsAjustement
                  .map((m) => ChoiceChip(
                        label: Text(m),
                        selected: _motif == m,
                        onSelected: (_) => setState(() => _motif = m),
                      ))
                  .toList(),
            ),
            const SizedBox(height: Espace.md),
            TextFormField(
              controller: _detailCtrl,
              decoration: const InputDecoration(
                labelText: 'Précision (optionnel)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: Espace.xl),

            // L'écart, dit en toutes lettres : c'est LUI que le gérant doit
            // valider, pas le nouveau total.
            Container(
              padding: const EdgeInsets.all(Espace.md),
              decoration: BoxDecoration(
                color: couleurEcart.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Rayon.md),
                border:
                    Border.all(color: couleurEcart.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Écart constaté', style: theme.textTheme.titleSmall),
                  Text(
                    ecart == 0
                        ? 'aucun'
                        : '${ecart > 0 ? '+' : '−'}${fmtNombre(ecart.abs())} ${widget.article.unite}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: couleurEcart,
                    ),
                  ),
                ],
              ),
            ),
            if (ecart < 0) ...[
              const SizedBox(height: Espace.sm),
              Text(
                'Cette correction retire de la marchandise du stock. Elle sera '
                'inscrite au journal, à votre nom.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Espace.lg),

            AppButton(
              label: _isSubmitting
                  ? 'Enregistrement…'
                  : "Enregistrer l'ajustement",
              icon: Icons.check_rounded,
              expanded: true,
              onPressed: _isSubmitting ? null : _valider,
            ),
          ],
        ),
      ),
    );
  }
}
