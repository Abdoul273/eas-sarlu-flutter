import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/sync/op_queue.dart';
import '../dashboard/dashboard_page.dart';

class MouvementSheet extends ConsumerStatefulWidget {
  final Article article;
  final String typePreChoisi;

  const MouvementSheet({
    super.key,
    required this.article,
    required this.typePreChoisi,
  });

  @override
  ConsumerState<MouvementSheet> createState() => _MouvementSheetState();
}

class _MouvementSheetState extends ConsumerState<MouvementSheet> {
  late TextEditingController _quantiteCtrl, _noteCtrl;
  String _type = '';
  int _quantite = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _type = widget.typePreChoisi;
    _quantiteCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
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
    super.dispose();
  }

  void _ajouterQuantite(int delta) {
    final actuel = parseMontantClean(_quantiteCtrl.text);
    final nouveau = (actuel + delta).clamp(0, 999999);
    _quantiteCtrl.text = nouveau.toString();
    _quantiteCtrl.selection = TextSelection.collapsed(offset: _quantiteCtrl.text.length);
  }

  int _stockApres() {
    switch (_type) {
      case 'entrée':
        return widget.article.stock + _quantite;
      case 'sortie':
        return widget.article.stock - _quantite;
      case 'ajustement':
        return _quantite;
      default:
        return widget.article.stock;
    }
  }

  Color _getTypeColor(BuildContext context) {
    final metier = context.metier;
    switch (_type) {
      case 'entrée':
        return metier.succes;
      case 'sortie':
        return metier.danger;
      case 'ajustement':
        return metier.alerte;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Future<void> _valider() async {
    final quantite = parseMontantClean(_quantiteCtrl.text);
    if (quantite <= 0 ||
        (_type == 'sortie' && quantite > widget.article.stock)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _type == 'sortie' && quantite > widget.article.stock
                      ? 'Stock insuffisant pour cette sortie'
                      : 'Veuillez saisir une quantité supérieure à 0',
                ),
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
      type: _type,
      quantite: quantite,
      date: DateTime.now().toIso8601String(),
      utilisateur: ref.read(utilisateurActuelProvider)?.nom ?? 'Utilisateur',
      note: _noteCtrl.text.trim(),
    );

    try {
      final opQueue = ref.read(opQueueProvider);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = _getTypeColor(context);
    final stockFinal = _stockApres();
    final isSurSortie = _type == 'sortie' && _quantite > widget.article.stock;
    final isSousStockMin = stockFinal <= widget.article.stockMin && stockFinal >= 0;

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

            // Article Header summary
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Rayon.sm),
                    ),
                    child: Icon(
                      _type == 'entrée'
                          ? Icons.add_business_rounded
                          : (_type == 'sortie'
                              ? Icons.local_shipping_rounded
                              : Icons.tune_rounded),
                      color: typeColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: Espace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.article.nom,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (widget.article.ref.isNotEmpty) ...[
                              Text(
                                widget.article.ref,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'Monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            BadgePastille(
                              texte: widget.article.categorie,
                              couleur: scheme.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            // Type Selector
            Text(
              'Type de mouvement',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Espace.xs),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'entrée',
                  label: const Text('Entrée'),
                  icon: Icon(Icons.arrow_downward_rounded,
                      color: _type == 'entrée' ? context.metier.succes : null),
                ),
                ButtonSegment(
                  value: 'sortie',
                  label: const Text('Sortie'),
                  icon: Icon(Icons.arrow_upward_rounded,
                      color: _type == 'sortie' ? context.metier.danger : null),
                ),
                ButtonSegment(
                  value: 'ajustement',
                  label: const Text('Ajustement'),
                  icon: Icon(Icons.tune_rounded,
                      color: _type == 'ajustement' ? context.metier.alerte : null),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (vals) => setState(() => _type = vals.first),
            ),
            const SizedBox(height: Espace.lg),

            // Quantity Input
            TextFormField(
              controller: _quantiteCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: typeColor,
              ),
              decoration: InputDecoration(
                labelText: _type == 'ajustement'
                    ? 'Nouveau stock total'
                    : 'Quantité (${_type == 'entrée' ? '+' : '-'})',
                suffixText: widget.article.unite,
                prefixIcon: Icon(Icons.numbers_rounded, color: typeColor),
              ),
            ),
            const SizedBox(height: Espace.sm),

            // Quick increment buttons
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Raccourcis: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  _buildQuickChip('+1', () => _ajouterQuantite(1), scheme),
                  _buildQuickChip('+5', () => _ajouterQuantite(5), scheme),
                  _buildQuickChip('+10', () => _ajouterQuantite(10), scheme),
                  _buildQuickChip('+50', () => _ajouterQuantite(50), scheme),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      _quantiteCtrl.clear();
                      setState(() => _quantite = 0);
                    },
                    borderRadius: BorderRadius.circular(Rayon.pilule),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'Effacer',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            // Stock Impact Live Card
            Container(
              padding: const EdgeInsets.all(Espace.md),
              decoration: BoxDecoration(
                color: isSurSortie
                    ? context.metier.dangerFond
                    : isSousStockMin
                        ? context.metier.alerteFond
                        : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Rayon.md),
                border: Border.all(
                  color: isSurSortie
                      ? context.metier.danger.withValues(alpha: 0.5)
                      : isSousStockMin
                          ? context.metier.alerte.withValues(alpha: 0.5)
                          : scheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Stock Actuel', style: theme.textTheme.bodySmall),
                          Text(
                            '${widget.article.stock} ${widget.article.unite}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        _type == 'entrée'
                            ? Icons.add_rounded
                            : (_type == 'sortie'
                                ? Icons.remove_rounded
                                : Icons.arrow_forward_rounded),
                        color: typeColor,
                        size: 24,
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Nouveau Stock', style: theme.textTheme.bodySmall),
                          Text(
                            '$stockFinal ${widget.article.unite}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isSurSortie
                                  ? context.metier.danger
                                  : (isSousStockMin
                                      ? context.metier.alerte
                                      : typeColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isSurSortie) ...[
                    const SizedBox(height: Espace.xs),
                    Row(
                      children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: context.metier.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Attention : La sortie ($_quantite) excède le stock disponible !',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: context.metier.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (isSousStockMin) ...[
                    const SizedBox(height: Espace.xs),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: context.metier.alerte),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Alerte : Le stock passera sous le seuil min (${widget.article.stockMin}) !',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: context.metier.alerte,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Espace.md),

            // Note input
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Motif / Note de mouvement (optionnel)',
                hintText: 'Ex: Commande client #104, livraison usine...',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: Espace.xl),

            // Validation button
            AppButton(
              label: _isSubmitting ? 'Envoi du mouvement…' : 'Valider le mouvement',
              icon: _type == 'entrée'
                  ? Icons.add_circle_rounded
                  : (_type == 'sortie' ? Icons.remove_circle_rounded : Icons.check_circle_rounded),
              loading: _isSubmitting,
              onPressed: _isSubmitting ? null : _valider,
              expanded: true,
            ),
            const SizedBox(height: Espace.xs),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, VoidCallback onTap, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rayon.pilule),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(Rayon.pilule),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
