import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import 'fournisseur_form_sheet.dart';

// ─── Choisir un fournisseur ───────────────────────────────────────────────────
//
// Le même geste sert à trois endroits : une entrée de marchandise, la création
// d'un article livré, et demain tout écran qui parlera d'achat. Il est écrit
// une fois. La feuille de mouvement en avait sa propre copie ; deux copies
// finissent toujours par se comporter différemment — l'une trie, l'autre non,
// l'une propose de créer un fournisseur, l'autre l'oublie.

final fournisseursDisponiblesProvider =
    StreamProvider.autoDispose<List<Fournisseur>>((ref) {
  return ref.watch(storesProvider).watchFournisseurs();
});

/// Ouvre la liste des fournisseurs et rend celui qui a été choisi.
///
/// Rend `null` si l'utilisateur referme sans choisir. Un fournisseur créé
/// depuis cette feuille est rendu directement : il n'a pas à être recherché
/// dans une liste où il vient à peine d'apparaître.
Future<Fournisseur?> choisirFournisseur(BuildContext context) {
  return showModalBottomSheet<Fournisseur>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ListeFournisseurs(),
  );
}

class _ListeFournisseurs extends ConsumerStatefulWidget {
  const _ListeFournisseurs();

  @override
  ConsumerState<_ListeFournisseurs> createState() => _ListeFournisseursState();
}

class _ListeFournisseursState extends ConsumerState<_ListeFournisseurs> {
  final _rechercheCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _rechercheCtrl.addListener(
        () => setState(() => _query = _rechercheCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    final cree = await showModalBottomSheet<Fournisseur>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FournisseurFormSheet(),
    );
    if (!mounted || cree == null) return;
    // Créé puis choisi d'un seul geste : c'est la raison d'être du bouton.
    Navigator.pop(context, cree);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(fournisseursDisponiblesProvider);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: Rayon.feuille,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PoigneeFeuille(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Espace.page, Espace.xs, Espace.page, Espace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choisir un fournisseur',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _creer,
                    icon: const Icon(Icons.add_business_rounded, size: 18),
                    label: const Text('Nouveau'),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Espace.page),
              child: TextField(
                controller: _rechercheCtrl,
                decoration: const InputDecoration(
                  hintText: 'Nom, téléphone ou quartier…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: Espace.sm),
            Flexible(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Espace.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(Espace.xl),
                  child: Text('Liste indisponible : $e'),
                ),
                data: (tous) {
                  final filtres = _query.isEmpty
                      ? tous
                      : tous
                          .where((f) =>
                              f.nom.toLowerCase().contains(_query) ||
                              f.telephone.toLowerCase().contains(_query) ||
                              f.quartier.toLowerCase().contains(_query))
                          .toList();

                  if (filtres.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(Espace.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.handshake_outlined,
                              size: 44, color: scheme.surfaceContainerHighest),
                          const SizedBox(height: Espace.md),
                          Text(
                            tous.isEmpty
                                ? 'Aucun fournisseur enregistré.'
                                : 'Aucun fournisseur ne correspond à cette recherche.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: Espace.md),
                          AppButton(
                            label: 'Ajouter un fournisseur',
                            icon: Icons.add_business_rounded,
                            onPressed: _creer,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: Espace.page),
                    itemCount: filtres.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final f = filtres[i];
                      final lieu = [f.quartier, f.ville]
                          .where((x) => x.isNotEmpty)
                          .join(', ');
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              scheme.primary.withValues(alpha: 0.1),
                          child: Text(
                            f.nom.isEmpty ? '?' : f.nom[0].toUpperCase(),
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(f.nom,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: [f.telephone, lieu]
                                .where((x) => x.isNotEmpty)
                                .isEmpty
                            ? null
                            : Text([f.telephone, lieu]
                                .where((x) => x.isNotEmpty)
                                .join(' · ')),
                        onTap: () => Navigator.pop(context, f),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
