import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../../core/db/stores.dart';
import '../../core/sync/op_queue.dart';
import '../dashboard/dashboard_page.dart';
import '../../app/theme.dart';

class ReglementSheet extends ConsumerStatefulWidget {
  final Depense depense;
  const ReglementSheet({super.key, required this.depense});

  @override
  ConsumerState<ReglementSheet> createState() => _ReglementSheetState();
}

class _ReglementSheetState extends ConsumerState<ReglementSheet> {
  late TextEditingController _montantCtrl;
  late TextEditingController _noteCtrl;
  String _mode = 'espèces';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final reste = resteAPayer(widget.depense);
    _montantCtrl = TextEditingController(
        text: reste > 0 ? fmtNombre(reste) : '');
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _montantCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_isSubmitting) return;
    final montantSaisi = parseMontantClean(_montantCtrl.text);
    if (montantSaisi <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saisissez un montant supérieur à zéro')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final stores = ref.read(storesProvider);
      final opQueue = ref.read(opQueueProvider);

      // Dépense RELUE au moment de valider : même règle que pour un versement
      // client — un règlement passé entre temps ne doit pas être ignoré.
      final depense =
          await stores.getDepense(widget.depense.id) ?? widget.depense;
      final reste = resteAPayer(depense);
      if (reste <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cette dépense est déjà réglée')));
        Navigator.pop(context, false);
        return;
      }
      if (montantSaisi > reste) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Le règlement dépasse le reste à payer (${fmtGNF(reste)})')));
        return;
      }

      final reglement = Reglement(
        id: const Uuid().v4(),
        date: DateTime.now().toIso8601String(),
        montant: montantSaisi,
        mode: _mode,
        note: _noteCtrl.text.trim(),
        utilisateur:
            ref.read(utilisateurActuelProvider)?.nom ?? 'Utilisateur',
      );

      // Ajout local optimiste. `reglements` peut être une liste constante
      // (dépense sans règlement) : on recrée la dépense au lieu de muter la
      // liste en place.
      await stores.upsert('depense', depense.avecReglement(reglement));

      await opQueue.enqueue('depense_reglement', {
        'depenseId': depense.id,
        'reglement': reglement.toJson(),
        if (depense.rev != null) 'baseRev': depense.rev,
      });

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
    final reste = resteAPayer(widget.depense);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rayon.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Poignée (Drag handle)
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(Rayon.xl),
              ),
            ),
          ),
          
          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(Espace.xl, Espace.lg, Espace.xl, Espace.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add_card_rounded, color: scheme.primary),
                ),
                const SizedBox(width: Espace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nouveau règlement',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Reste à régler : ${fmtGNF(reste)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Formulaire
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(Espace.xl, Espace.lg, Espace.xl, Espace.xl + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(Espace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ChampMontant(
                          controller: _montantCtrl,
                          labelText: 'Montant à régler *',
                          autofocus: true,
                        ),
                        const SizedBox(height: Espace.md),
                        DropdownButtonFormField<String>(
                          initialValue: _mode,
                          decoration: InputDecoration(
                            labelText: 'Mode de paiement',
                            filled: true,
                            fillColor: scheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Rayon.md),
                              borderSide: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                          items: ['espèces', 'mobile money', 'virement', 'chèque']
                              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) => setState(() => _mode = v!),
                        ),
                        const SizedBox(height: Espace.md),
                        TextField(
                          controller: _noteCtrl,
                          decoration: InputDecoration(
                            labelText: 'Note (optionnel)',
                            hintText: 'Ex: Par chèque n° 1234...',
                            filled: true,
                            fillColor: scheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Rayon.md),
                              borderSide: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Espace.xl),
                  AppButton(
                    label: _isSubmitting ? 'Enregistrement…' : 'Valider le règlement',
                    icon: Icons.check_circle_rounded,
                    onPressed: _isSubmitting ? null : _valider,
                    expanded: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
