import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';

import '../../core/models/models.dart';
import '../../core/sync/op_queue.dart';
import '../dashboard/dashboard_page.dart';

class DepenseFormPage extends ConsumerStatefulWidget {
  final Depense? depense; // null = création
  const DepenseFormPage({super.key, this.depense});

  @override
  ConsumerState<DepenseFormPage> createState() => _DepenseFormPageState();
}

class _DepenseFormPageState extends ConsumerState<DepenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _libelleCtrl,
      _beneficiaireCtrl,
      _montantCtrl,
      _referenceCtrl,
      _noteCtrl;
  String _categorie = 'Divers';
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;

  /// Le catalogue, plus la catégorie de la dépense en cours si elle n'en fait
  /// pas partie. Une dépense enregistrée jadis sous un libellé disparu du
  /// catalogue garde le sien : la modifier ne doit pas la reclasser en douce.
  List<String> get _categoriesProposees {
    final cles = categoriesDepenseDef.map((c) => c.cle).toList();
    return cles.contains(_categorie) ? cles : [_categorie, ...cles];
  }

  @override
  void initState() {
    super.initState();
    final d = widget.depense;
    _libelleCtrl = TextEditingController(text: d?.libelle ?? '');
    _beneficiaireCtrl = TextEditingController(text: d?.beneficiaire ?? '');
    _montantCtrl = TextEditingController(
        text: d != null && d.montant > 0 ? fmtNombre(d.montant) : '');
    _referenceCtrl = TextEditingController(text: d?.reference ?? '');
    _noteCtrl = TextEditingController(text: d?.note ?? '');
    if (d != null) {
      _categorie = d.categorie.isNotEmpty ? d.categorie : 'Divers';
      if (d.date.isNotEmpty) {
        _date = DateTime.tryParse(d.date) ?? DateTime.now();
      }
    }
  }

  @override
  void dispose() {
    _libelleCtrl.dispose();
    _beneficiaireCtrl.dispose();
    _montantCtrl.dispose();
    _referenceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;

    final montant = parseMontantClean(_montantCtrl.text);
    if (montant <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez saisir un montant valide (> 0 GNF)')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final stores = ref.read(storesProvider);
      final opQueue = ref.read(opQueueProvider);

      // En modification, on repart de la dépense TELLE QU'ELLE EST en base,
      // pas de la copie reçue à l'ouverture : un règlement encaissé entre
      // temps (par un collègue, par synchronisation) serait sinon effacé
      // par cette écriture.
      final existante = widget.depense == null
          ? null
          : (await stores.getDepense(widget.depense!.id) ?? widget.depense);

      // On ne descend jamais une dépense sous ce qui a déjà été versé au
      // bénéficiaire : le magasin se retrouverait créancier de son
      // fournisseur sans que personne ne l'ait décidé. Même règle que pour
      // une vente déjà encaissée.
      if (existante != null) {
        final regle = montantRegle(existante);
        if (montant < regle) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${fmtGNF(regle)} ont déjà été réglés sur cette '
                'dépense : son montant ne peut pas descendre en dessous.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ));
          return;
        }
      }

      final depense = Depense(
        id: existante?.id ?? const Uuid().v4(),
        numero: existante?.numero ?? '',
        date: _date.toIso8601String(),
        categorie: _categorie,
        libelle: _libelleCtrl.text.trim(),
        beneficiaire: _beneficiaireCtrl.text.trim(),
        montant: montant,
        reference: _referenceCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        // Celui qui a SAISI la dépense reste son auteur ; une correction ne
        // réécrit pas l'histoire.
        creePar: existante?.creePar.isNotEmpty == true
            ? existante!.creePar
            : ref.read(utilisateurActuelProvider)?.nom ?? 'Utilisateur',
        // `nature` et `statut` ne sont pas passés : ils se déduisent de la
        // catégorie et des règlements. Les saisir ici, c'est risquer de les
        // écrire faux.
        reglements: existante?.reglements ?? const [],
        rev: existante?.rev,
        updatedAt: existante?.updatedAt,
        updatedBy: existante?.updatedBy,
      );
      final baseRev = existante?.rev;

      await stores.upsert('depense', depense);
      await opQueue.enqueue('depense', {
        'record': depense.toJson(),
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
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.depense != null
              ? 'Modifier la dépense'
              : 'Nouvelle dépense')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: const Text('Date'),
                subtitle: Text(fmtDate(_date)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (date != null && mounted) setState(() => _date = date);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _libelleCtrl,
                decoration: const InputDecoration(labelText: 'Libellé *'),
                validator: (v) => v!.trim().isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              // La catégorie se choisit dans le catalogue, et c'est elle qui
              // décide de la nature comptable. Cet écran laissait auparavant
              // taper une catégorie libre ET choisir la nature à la main : on
              // pouvait enregistrer un loyer en « investissement ». La nature
              // est désormais affichée, pas saisie.
              DropdownButtonFormField<String>(
                initialValue: _categorie,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Catégorie *'),
                items: _categoriesProposees
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _categorie = v!),
              ),
              const SizedBox(height: 8),
              _EncartNature(categorie: _categorie),
              const SizedBox(height: 12),
              TextFormField(
                controller: _beneficiaireCtrl,
                decoration: const InputDecoration(labelText: 'Bénéficiaire'),
              ),
              const SizedBox(height: 12),
              ChampMontant(
                controller: _montantCtrl,
                labelText: 'Montant *',
                onChangedMontant: (_) {},
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referenceCtrl,
                decoration: const InputDecoration(
                    labelText: 'Référence (ex: facture fournisseur)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              AppButton(
                label: _isSubmitting ? 'Enregistrement…' : 'Enregistrer',
                icon: Icons.save,
                onPressed: _isSubmitting ? null : _enregistrer,
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ce que la catégorie choisie entraîne, dit avant d'enregistrer.
///
/// Sans cet encart, un utilisateur qui voit une dépense de 5 000 000 GNF ne pas
/// bouger le résultat du mois croit à un bug. C'est la transposition de
/// `EXPLICATION_NATURE` et `aideDe` de l'application web : la nature n'est pas
/// un choix, mais elle ne doit pas être une surprise.
class _EncartNature extends StatelessWidget {
  final String categorie;

  const _EncartNature({required this.categorie});

  @override
  Widget build(BuildContext context) {
    final nature = natureDe(categorie);
    final couleur = Color(couleurNature[nature] ?? 0xffE85D04);
    final aide = aideDe(categorie);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: couleur),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  libelleNature[nature] ?? nature,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: couleur, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(explicationNature(nature),
              style: const TextStyle(fontSize: 12, height: 1.35)),
          if (aide.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(aide,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
