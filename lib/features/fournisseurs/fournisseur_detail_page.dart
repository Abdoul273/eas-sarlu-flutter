import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import 'fournisseur_form_sheet.dart';

final fournisseurStreamProvider = StreamProvider.family<Fournisseur?, String>((ref, id) {
  final stores = ref.watch(storesProvider);
  return stores.watchFournisseur(id);
});

final achatsFournisseurProvider = StreamProvider.family<List<MouvementStock>, String>((ref, fournisseurId) {
  final stores = ref.watch(storesProvider);
  return stores.watchMouvements().map((mouvements) => 
    mouvements.where((m) => m.fournisseurId == fournisseurId && m.type == 'entrée').toList()
  );
});

class FournisseurDetailPage extends ConsumerWidget {
  final String id;
  const FournisseurDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fournisseurAsync = ref.watch(fournisseurStreamProvider(id));
    return fournisseurAsync.when(
      data: (fournisseur) {
        if (fournisseur == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EtatVide(message: 'Fournisseur introuvable'),
          );
        }
        return _FournisseurDetailBody(fournisseur: fournisseur);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Erreur: $e'))),
    );
  }
}

class _FournisseurDetailBody extends ConsumerWidget {
  final Fournisseur fournisseur;
  const _FournisseurDetailBody({required this.fournisseur});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achatsAsync = ref.watch(achatsFournisseurProvider(fournisseur.id));
    final achats = achatsAsync.valueOrNull ?? [];

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = fournisseur.nom.isNotEmpty ? fournisseur.nom[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fournisseur.nom,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Détails du fournisseur',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => FournisseurFormSheet(fournisseur: fournisseur),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          children: [
            const SizedBox(height: Espace.md),
            // Header Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espace.page),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: Espace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fournisseur.nom,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (fournisseur.telephone.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.phone_outlined,
                                  size: 14, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                fournisseur.telephone,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
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
            const SizedBox(height: Espace.lg),

            // Actions rapides (Appel / WhatsApp)
            if (fournisseur.telephone.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.phone),
                        label: const Text('Appeler'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.primary,
                          side: BorderSide(color: scheme.primary),
                        ),
                        onPressed: () async {
                          final uri = Uri.parse('tel:${fournisseur.telephone}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: Espace.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.message),
                        label: const Text('WhatsApp'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                        ),
                        onPressed: () async {
                          final uri = Uri.parse('https://wa.me/${fournisseur.telephone.replaceAll(' ', '')}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.lg),
            ],

            // Bloc infos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espace.page),
              child: AppCard(
                padding: const EdgeInsets.all(Espace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (fournisseur.email.isNotEmpty)
                      _InfoLigne(
                        icone: Icons.email_outlined,
                        label: 'Email',
                        valeur: fournisseur.email,
                      ),
                    if (fournisseur.adresse.isNotEmpty)
                      _InfoLigne(
                        icone: Icons.location_on_outlined,
                        label: 'Adresse',
                        valeur: fournisseur.adresse,
                      ),
                    if (fournisseur.quartier.isNotEmpty)
                      _InfoLigne(
                        icone: Icons.map_outlined,
                        label: 'Quartier',
                        valeur: fournisseur.quartier,
                      ),
                    if (fournisseur.ville.isNotEmpty)
                      _InfoLigne(
                        icone: Icons.location_city_outlined,
                        label: 'Ville',
                        valeur: fournisseur.ville,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: Espace.xl),

            // Historique des achats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espace.page),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Historique des achats',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.sm),
            if (achats.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Espace.lg),
                child: EtatVide(message: 'Aucun achat enregistré.'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                itemCount: achats.length,
                itemBuilder: (context, i) {
                  final achat = achats[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: AppCard(
                      padding: const EdgeInsets.all(Espace.md),
                      onTap: () {
                        context.pushNamed(
                          'detail-article',
                          pathParameters: {'id': achat.articleId},
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Achat du ${fmtDateCourt(DateTime.parse(achat.date))}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '+${fmtNombre(achat.quantite)}',
                                style: TextStyle(
                                  color: context.metier.succes,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Icon(Icons.chevron_right, color: scheme.outline),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoLigne extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valeur;

  const _InfoLigne({
    required this.icone,
    required this.label,
    required this.valeur,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Espace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: Espace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(valeur),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
