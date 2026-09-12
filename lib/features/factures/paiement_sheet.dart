import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../../core/db/stores.dart';
import '../../core/sync/op_queue.dart';
import '../dashboard/dashboard_page.dart';

class PaiementSheet extends ConsumerStatefulWidget {
  final Facture facture;
  const PaiementSheet({super.key, required this.facture});

  @override
  ConsumerState<PaiementSheet> createState() => _PaiementSheetState();
}

class _PaiementSheetState extends ConsumerState<PaiementSheet> {
  late TextEditingController _montantCtrl;
  late TextEditingController _noteCtrl;
  String _mode = 'espèces';
  bool _isSubmitting = false;

  final _modes = const [
    {'id': 'espèces', 'label': 'Espèces', 'icon': Icons.payments_rounded},
    {
      'id': 'mobile money',
      'label': 'Mobile Money',
      'icon': Icons.phone_android_rounded
    },
    {'id': 'virement', 'label': 'Virement', 'icon': Icons.account_balance_rounded},
    {'id': 'chèque', 'label': 'Chèque', 'icon': Icons.description_rounded},
  ];

  @override
  void initState() {
    super.initState();
    final reste = resteDu(widget.facture);
    _montantCtrl =
        TextEditingController(text: reste > 0 ? fmtNombre(reste) : '');
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
        const SnackBar(content: Text('Saisissez un montant supérieur à zéro')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final opQueue = ref.read(opQueueProvider);
      final stores = ref.read(storesProvider);

      // La facture est RELUE au moment de valider, pas prise telle qu'elle
      // était à l'ouverture de la feuille : un versement encaissé entre
      // temps sur un autre poste, ou arrivé par synchronisation, aurait
      // sinon été ignoré — et le client aurait payé deux fois.
      final facture =
          await stores.getFacture(widget.facture.id) ?? widget.facture;
      final reste = resteDu(facture);
      if (reste <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cette facture est déjà soldée')),
        );
        Navigator.pop(context, false);
        return;
      }
      if (montantSaisi > reste) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Le versement dépasse le reste dû (${fmtGNF(reste)})'),
        ));
        return;
      }

      final paiement = Paiement(
        id: const Uuid().v4(),
        date: DateTime.now().toIso8601String(),
        montant: montantSaisi,
        mode: _mode,
        note: _noteCtrl.text.trim(),
        utilisateur:
            ref.read(utilisateurActuelProvider)?.nom ?? 'Utilisateur',
      );

      await stores.upsert('facture', facture.avecPaiement(paiement));

      await opQueue.enqueue('facture_paiement', {
        'factureId': facture.id,
        'paiement': paiement.toJson(),
        if (facture.rev != null) 'baseRev': facture.rev,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;
    final reste = resteDu(widget.facture);

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
                    // En-tête Banner Card (Style VenteDetailSheet)
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
                            child: Icon(
                              Icons.payments_rounded,
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
                                  'Facture ${widget.facture.numero}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                BadgePastille(
                                  texte: 'Reste dû: ${fmtGNF(reste)}',
                                  couleur: metier.danger,
                                  icone: Icons.account_balance_wallet_rounded,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: Espace.lg),

                    // Raccourcis de Montants Saisis
                    Row(
                      children: [
                        Expanded(
                          child: ActionChip(
                            avatar: Icon(Icons.check_circle_rounded,
                                size: 16, color: scheme.primary),
                            label: const Text('Tout solder (100%)'),
                            onPressed: () {
                              setState(() => _montantCtrl.text = fmtNombre(reste));
                            },
                          ),
                        ),
                        const SizedBox(width: Espace.xs),
                        ActionChip(
                          avatar: Icon(Icons.pie_chart_rounded,
                              size: 16, color: scheme.secondary),
                          label: const Text('50%'),
                          onPressed: () {
                            setState(
                                () => _montantCtrl.text = fmtNombre(reste ~/ 2));
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: Espace.md),

                    // Section Montant et Mode de paiement
                    AppCard(
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ChampMontant(
                            controller: _montantCtrl,
                            labelText: 'Montant à encaisser *',
                            autofocus: true,
                          ),
                          const SizedBox(height: Espace.md),

                          Text(
                            'Mode de règlement',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Espace.xs + 2),
                          Wrap(
                            spacing: Espace.xs,
                            runSpacing: Espace.xs,
                            children: _modes.map((modeItem) {
                              final isSelected = _mode == modeItem['id'];
                              return ChoiceChip(
                                avatar: Icon(
                                  modeItem['icon'] as IconData,
                                  size: 16,
                                  color: isSelected
                                      ? scheme.onPrimary
                                      : scheme.onSurfaceVariant,
                                ),
                                label: Text(modeItem['label'] as String),
                                selected: isSelected,
                                selectedColor: scheme.primary,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (sel) {
                                  if (sel) {
                                    setState(
                                        () => _mode = modeItem['id'] as String);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: Espace.md),

                          TextFormField(
                            controller: _noteCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Note / Remarque (optionnel)',
                              hintText: 'Ex: Avance par Orange Money',
                              prefixIcon: Icon(Icons.notes_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bouton d'Action Inférieur (Orange Marque)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(Espace.page),
                  child: AppButton(
                    label: _isSubmitting
                        ? 'Enregistrement…'
                        : 'Valider le versement',
                    icon: Icons.check_circle_rounded,
                    onPressed: _isSubmitting ? null : _valider,
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
