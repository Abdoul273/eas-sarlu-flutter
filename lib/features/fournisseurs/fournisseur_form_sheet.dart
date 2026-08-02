import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../../core/db/stores.dart';
import '../../core/sync/op_queue.dart';

class FournisseurFormSheet extends ConsumerStatefulWidget {
  final Fournisseur? fournisseur;
  const FournisseurFormSheet({super.key, this.fournisseur});

  @override
  ConsumerState<FournisseurFormSheet> createState() => _FournisseurFormSheetState();
}

class _FournisseurFormSheetState extends ConsumerState<FournisseurFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomCtrl,
      _telephoneCtrl,
      _emailCtrl,
      _adresseCtrl,
      _quartierCtrl,
      _villeCtrl;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nomCtrl = TextEditingController(text: widget.fournisseur?.nom ?? '');
    _telephoneCtrl = TextEditingController(text: widget.fournisseur?.telephone ?? '');
    _emailCtrl = TextEditingController(text: widget.fournisseur?.email ?? '');
    _adresseCtrl = TextEditingController(text: widget.fournisseur?.adresse ?? '');
    _quartierCtrl = TextEditingController(text: widget.fournisseur?.quartier ?? '');
    _villeCtrl = TextEditingController(text: widget.fournisseur?.ville ?? '');
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _telephoneCtrl.dispose();
    _emailCtrl.dispose();
    _adresseCtrl.dispose();
    _quartierCtrl.dispose();
    _villeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final fournisseur = Fournisseur(
      id: widget.fournisseur?.id ?? const Uuid().v4(),
      nom: _nomCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      telephone: _telephoneCtrl.text.trim(),
      adresse: _adresseCtrl.text.trim(),
      quartier: _quartierCtrl.text.trim(),
      ville: _villeCtrl.text.trim(),
      creeLe: widget.fournisseur?.creeLe ?? DateTime.now().toIso8601String(),
    );

    try {
      final stores = ref.read(storesProvider);
      final opQueue = ref.read(opQueueProvider);
      final baseRev = widget.fournisseur?.rev;

      await stores.upsert('fournisseur', fournisseur);
      await opQueue.enqueue('fournisseur', {
        'record': fournisseur.toJson(),
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
    final isEdit = widget.fournisseur != null;

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
                      // Header Banner Card
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
                                        ? 'Modifier le fournisseur'
                                        : 'Nouveau fournisseur',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Les champs marqués d\'un astérisque (*) sont obligatoires.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Espace.lg),

                      Text(
                        'Informations générales',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: Espace.sm),

                      TextFormField(
                        controller: _nomCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nom / Raison sociale *',
                          prefixIcon: Icon(Icons.business),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Le nom est requis'
                            : null,
                      ),
                      const SizedBox(height: Espace.md),
                      TextFormField(
                        controller: _telephoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Téléphone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: Espace.md),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: Espace.xl),

                      Text(
                        'Adresse',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: Espace.sm),

                      TextFormField(
                        controller: _quartierCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Quartier',
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                      ),
                      const SizedBox(height: Espace.md),
                      TextFormField(
                        controller: _adresseCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Adresse exacte',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: Espace.md),
                      TextFormField(
                        controller: _villeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ville',
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),

                Container(
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
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
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
                          onPressed: _isSubmitting ? null : _enregistrer,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Rayon.pilule),
                            ),
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Enregistrer',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ],
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
