import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../../core/db/stores.dart';

final tousFournisseursProvider = StreamProvider<List<Fournisseur>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchFournisseurs();
});

final fournisseursFiltresProvider =
    Provider.family<List<Fournisseur>, String>((ref, query) {
  final fournisseursAsync = ref.watch(tousFournisseursProvider);
  final fournisseurs = fournisseursAsync.valueOrNull ?? [];
  if (query.isEmpty) return fournisseurs;
  final q = query.toLowerCase().trim();
  return fournisseurs
      .where((c) =>
          c.nom.toLowerCase().contains(q) ||
          c.telephone.toLowerCase().contains(q) ||
          c.quartier.toLowerCase().contains(q))
      .toList();
});

final fournisseursGroupesProvider =
    Provider.family<Map<String, List<Fournisseur>>, String>((ref, query) {
  final fournisseurs = ref.watch(fournisseursFiltresProvider(query));
  final map = <String, List<Fournisseur>>{};
  for (final fournisseur in fournisseurs) {
    final letter = fournisseur.nom.isNotEmpty ? fournisseur.nom[0].toUpperCase() : '?';
    map.putIfAbsent(letter, () => []).add(fournisseur);
  }
  for (final list in map.values) {
    list.sort((a, b) => a.nom.compareTo(b.nom));
  }
  return Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
});

class FournisseursPage extends ConsumerStatefulWidget {
  const FournisseursPage({super.key});

  @override
  ConsumerState<FournisseursPage> createState() => _FournisseursPageState();
}

class _FournisseursPageState extends ConsumerState<FournisseursPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onLetterTap(String letter) {
    setState(() {
      if (_query == letter) {
        _query = '';
      } else {
        _query = letter;
        _searchController.text = letter;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fournisseursAsync = ref.watch(tousFournisseursProvider);
    final fournisseursList = fournisseursAsync.valueOrNull ?? [];
    final groupes = ref.watch(fournisseursGroupesProvider(_query));
    final letters = groupes.keys.toList();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;


    return Column(
      children: [
        // En-tête Hero Gradient Marque (Identique aux autres pages)
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Espace.page, Espace.sm, Espace.page, Espace.xs),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Espace.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Rayon.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  Color.lerp(scheme.primary, const Color(0xFFE85D04), 0.5)!,
                  const Color(0xFFC23E00),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.people_alt_rounded,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: Espace.md),
                        const Text(
                          'Répertoire Fournisseurs',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${fournisseursList.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),
        ),

        // Barre de Recherche
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espace.page),
          child: AppSearchBar(
            controller: _searchController,
            hintText: 'Rechercher par nom, téléphone, quartier…',
          ),
        ),
        const SizedBox(height: Espace.xs),

        Expanded(
          child: groupes.isEmpty
              ? const EtatVide(
                  icone: Icons.people_alt_outlined,
                  message: 'Aucun fournisseur trouvé',
                  description:
                      'Ajoutez votre premier fournisseur pour le retrouver ici et lors des ventes.',
                )
              : Row(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.only(bottom: Espace.basDeListe),
                        itemCount: letters.length,
                        itemBuilder: (context, i) {
                          final letter = letters[i];
                          final fournisseursGroup = groupes[letter]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Espace.page,
                                  Espace.md,
                                  Espace.page,
                                  Espace.xs,
                                ),
                                child: Text(
                                  letter,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              for (final fournisseur in fournisseursGroup)
                                _FournisseurTile(
                                  fournisseur: fournisseur,
                                  onTap: () => context.pushNamed(
                                    'detail-fournisseur',
                                    pathParameters: {'id': fournisseur.id},
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    // Index alphabétique
                    _AlphabetIndex(
                      letters: letters,
                      onLetterTap: _onLetterTap,
                      selectedLetter: _query.length == 1 ? _query : null,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}



class _FournisseurTile extends StatelessWidget {
  final Fournisseur fournisseur;
  final VoidCallback onTap;

  const _FournisseurTile({required this.fournisseur, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = scheme.primary;
    final initial = fournisseur.nom.isNotEmpty ? fournisseur.nom[0].toUpperCase() : '?';
    final sousTitre =
        fournisseur.telephone.isNotEmpty ? fournisseur.telephone : fournisseur.quartier;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Espace.page,
        vertical: 4,
      ),
      child: AppCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(Espace.md),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1,
                  color: typeColor,
                ),
              ),
            ),
            const SizedBox(width: Espace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fournisseur.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sousTitre.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          fournisseur.telephone.isNotEmpty
                              ? Icons.phone_outlined
                              : Icons.location_on_outlined,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            sousTitre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

class _AlphabetIndex extends StatelessWidget {
  final List<String> letters;
  final ValueChanged<String> onLetterTap;
  final String? selectedLetter;

  const _AlphabetIndex({
    required this.letters,
    required this.onLetterTap,
    this.selectedLetter,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 28,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final letter in letters)
                  _Lettre(
                    lettre: letter,
                    actif: selectedLetter == letter,
                    couleurActive: scheme.primary,
                    couleurInactive: scheme.onSurfaceVariant,
                    onTap: () => onLetterTap(letter),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Lettre extends StatelessWidget {
  final String lettre;
  final bool actif;
  final Color couleurActive;
  final Color couleurInactive;
  final VoidCallback onTap;

  const _Lettre({
    required this.lettre,
    required this.actif,
    required this.couleurActive,
    required this.couleurInactive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.symmetric(vertical: 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: actif
              ? couleurActive.withValues(alpha: 0.14)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(
          lettre,
          style: TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: actif ? FontWeight.w800 : FontWeight.w500,
            color: actif ? couleurActive : couleurInactive,
          ),
        ),
      ),
    );
  }
}
