import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../../core/db/stores.dart';
import '../../core/sync/op_queue.dart';

class ClientFormSheet extends ConsumerStatefulWidget {
  final Client? client;
  const ClientFormSheet({super.key, this.client});

  @override
  ConsumerState<ClientFormSheet> createState() => _ClientFormSheetState();
}

class _ClientFormSheetState extends ConsumerState<ClientFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomCtrl,
      _telephoneCtrl,
      _adresseCtrl,
      _quartierCtrl,
      _villeCtrl;
  String _type = 'particulier';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nomCtrl = TextEditingController(text: widget.client?.nom ?? '');
    _telephoneCtrl =
        TextEditingController(text: widget.client?.telephone ?? '');
    _adresseCtrl = TextEditingController(text: widget.client?.adresse ?? '');
    _quartierCtrl = TextEditingController(text: widget.client?.quartier ?? '');
    _villeCtrl = TextEditingController(text: widget.client?.ville ?? '');
    if (widget.client != null) {
      _type = widget.client!.type;
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _telephoneCtrl.dispose();
    _adresseCtrl.dispose();
    _quartierCtrl.dispose();
    _villeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final client = Client(
      id: widget.client?.id ?? const Uuid().v4(),
      nom: _nomCtrl.text.trim(),
      type: _type,
      email: widget.client?.email ?? '',
      telephone: _telephoneCtrl.text.trim(),
      adresse: _adresseCtrl.text.trim(),
      quartier: _quartierCtrl.text.trim(),
      ville: _villeCtrl.text.trim(),
      creeLe: widget.client?.creeLe ?? DateTime.now().toIso8601String(),
    );

    try {
      final stores = ref.read(storesProvider);
      final opQueue = ref.read(opQueueProvider);
      final baseRev = widget.client?.rev;

      await stores.upsert('client', client);
      await opQueue.enqueue('client', {
        'record': client.toJson(),
        if (baseRev != null) 'baseRev': baseRev,
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
    final isEdit = widget.client != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: Rayon.feuille,
          ),
          child: Form(
            key: _formKey,
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
                      // Header Banner Card (Style VenteDetailSheet)
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
                                isEdit
                                    ? Icons.manage_accounts_rounded
                                    : Icons.person_add_rounded,
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
                                    isEdit
                                        ? 'Modifier le Client'
                                        : 'Nouveau Client',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  BadgePastille(
                                    texte: isEdit
                                        ? 'Fiche répertoire'
                                        : 'Ajout catalogue',
                                    couleur: scheme.primary,
                                    icone: Icons.person_rounded,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: Espace.lg),

                      // Formulaire
                      AppCard(
                        margin: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _nomCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nom complet ou Raison sociale *',
                                hintText: 'Ex: Mamadou Diallo ou SARL Alpha',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => v!.trim().isEmpty
                                  ? 'Le nom est obligatoire'
                                  : null,
                            ),
                            const SizedBox(height: Espace.md),

                            Text(
                              'Type de client',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: Espace.xs + 2),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'particulier',
                                  label: Text('Particulier'),
                                  icon: Icon(Icons.person_rounded),
                                ),
                                ButtonSegment(
                                  value: 'professionnel',
                                  label: Text('Professionnel'),
                                  icon: Icon(Icons.business_center_rounded),
                                ),
                              ],
                              selected: {_type},
                              onSelectionChanged: (vals) =>
                                  setState(() => _type = vals.first),
                            ),
                            const SizedBox(height: Espace.md),

                            TextFormField(
                              controller: _telephoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Téléphone',
                                hintText: 'Ex: +224 620 00 00 00',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: Espace.md),

                            TextFormField(
                              controller: _adresseCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Adresse',
                                hintText: 'Ex: Rue KA 002',
                                prefixIcon: Icon(Icons.location_on_outlined),
                              ),
                            ),
                            const SizedBox(height: Espace.md),

                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _quartierCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Quartier',
                                      hintText: 'Ex: Camayenne',
                                      prefixIcon: Icon(Icons.map_outlined),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: Espace.md),
                                Expanded(
                                  child: TextFormField(
                                    controller: _villeCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Ville',
                                      hintText: 'Ex: Conakry',
                                      prefixIcon:
                                          Icon(Icons.location_city_outlined),
                                    ),
                                  ),
                                ),
                              ],
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
                          : (isEdit ? 'Mettre à jour' : 'Enregistrer le client'),
                      icon: Icons.check_circle_rounded,
                      onPressed: _isSubmitting ? null : _enregistrer,
                      expanded: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
