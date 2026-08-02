import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../dashboard/dashboard_page.dart'; // toutesVentesProvider, toutesFacturesProvider
import '../ventes/vente_detail_sheet.dart';
import 'client_form_sheet.dart';

final ventesClientProvider =
    Provider.family<List<Vente>, String>((ref, clientId) {
  final ventesAsync = ref.watch(toutesVentesProvider);
  return ventesAsync.valueOrNull
          ?.where((v) => v.clientId == clientId)
          .toList() ??
      [];
});

final facturesClientProvider =
    Provider.family<List<Facture>, String>((ref, clientId) {
  final facturesAsync = ref.watch(toutesFacturesProvider);
  return facturesAsync.valueOrNull
          ?.where((f) => f.clientId == clientId)
          .toList() ??
      [];
});

final totalAcheteClientProvider = Provider.family<int, String>((ref, clientId) {
  final ventes = ref.watch(ventesClientProvider(clientId));
  return ventes.fold<int>(0, (sum, v) => sum + v.totalNet);
});

final totalRestantDuClientProvider =
    Provider.family<int, String>((ref, clientId) {
  final factures = ref.watch(facturesClientProvider(clientId));
  return soldeClient(factures);
});

final avoirClientProvider =
    Provider.family<int, String>((ref, clientId) {
  final factures = ref.watch(facturesClientProvider(clientId));
  return avoirClient(factures);
});

class ClientDetailPage extends ConsumerWidget {
  final String id;
  const ClientDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientStreamProvider(id));
    return clientAsync.when(
      data: (client) {
        if (client == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EtatVide(message: 'Client introuvable'),
          );
        }
        return _ClientDetailBody(client: client);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Erreur: $e'))),
    );
  }
}

class _ClientDetailBody extends ConsumerWidget {
  final Client client;
  const _ClientDetailBody({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAchete = ref.watch(totalAcheteClientProvider(client.id));
    final totalRestantDu = ref.watch(totalRestantDuClientProvider(client.id));
    final ventes = ref.watch(ventesClientProvider(client.id));

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;
    final pro = client.type == 'professionnel';
    final typeColor = pro ? metier.info : metier.succes;
    final initial = client.nom.isNotEmpty ? client.nom[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              client.nom,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              pro ? 'Client Professionnel' : 'Client Particulier',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Modifier la fiche',
            onPressed: () => _modifierClient(context, client),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Espace.page,
          Espace.sm,
          Espace.page,
          Espace.basDeListe,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Carte Header Banner Profil
            AppCard(
              margin: EdgeInsets.zero,
              accent: typeColor,
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: typeColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              client.nom,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            BadgePastille(
                              texte: pro ? 'Professionnel' : 'Particulier',
                              couleur: typeColor,
                              icone: pro
                                  ? Icons.business_center_rounded
                                  : Icons.person_rounded,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (client.telephone.isNotEmpty) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Appeler',
                            icon: Icons.phone_rounded,
                            isTonal: true,
                            onPressed: () => _lancerAppel(client.telephone),
                          ),
                        ),
                        const SizedBox(width: Espace.sm),
                        Expanded(
                          child: AppButton(
                            label: 'WhatsApp',
                            icon: Icons.chat_rounded,
                            isTonal: true,
                            onPressed: () => _lancerWhatsApp(context, client.telephone),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            // Section Coordonnées & Localisation
            const SectionHeader(
              titre: 'Coordonnées & Adresses',
              icone: Icons.contact_phone_rounded,
            ),
            const SizedBox(height: Espace.sm),
            AppCard(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (client.telephone.isNotEmpty) ...[
                    _InfoRowTile(
                      icone: Icons.phone_outlined,
                      label: 'Téléphone',
                      valeur: client.telephone,
                    ),
                    const Divider(height: 1),
                  ],
                  if (client.email.isNotEmpty) ...[
                    _InfoRowTile(
                      icone: Icons.email_outlined,
                      label: 'Email',
                      valeur: client.email,
                    ),
                    const Divider(height: 1),
                  ],
                  if (client.adresse.isNotEmpty) ...[
                    _InfoRowTile(
                      icone: Icons.location_on_outlined,
                      label: 'Adresse',
                      valeur: client.adresse,
                    ),
                    const Divider(height: 1),
                  ],
                  if (client.quartier.isNotEmpty) ...[
                    _InfoRowTile(
                      icone: Icons.map_outlined,
                      label: 'Quartier',
                      valeur: client.quartier,
                    ),
                    const Divider(height: 1),
                  ],
                  if (client.ville.isNotEmpty)
                    _InfoRowTile(
                      icone: Icons.location_city_outlined,
                      label: 'Ville',
                      valeur: client.ville,
                    ),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            // Section Statistiques & Activité Client
            const SectionHeader(
              titre: 'Activité & Chiffres Clés',
              icone: Icons.insights_rounded,
            ),
            const SizedBox(height: Espace.sm),
            Row(
              children: [
                Expanded(
                  child: AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shopping_bag_outlined,
                                size: 16, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Total Acheté',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            fmtGNF(totalAchete),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Espace.md),
                Expanded(
                  child: AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                size: 16,
                                color: totalRestantDu > 0
                                    ? metier.danger
                                    : metier.succes),
                            const SizedBox(width: 6),
                            Text(
                              'Reste Dû',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            fmtGNF(totalRestantDu),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: totalRestantDu > 0
                                  ? metier.danger
                                  : metier.succes,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espace.lg),

            // Bouton Nouvelle Vente (Bouton Orange)
            AppButton(
              label: 'Nouvelle vente pour ce client',
              icon: Icons.add_shopping_cart_rounded,
              expanded: true,
              onPressed: () {
                context.pushNamed('nouvelle-vente',
                    queryParameters: {'clientId': client.id});
              },
            ),
            const SizedBox(height: Espace.xl),

            // Historique des ventes
            const SectionHeader(
              titre: 'Historique des Ventes',
              icone: Icons.receipt_long_rounded,
            ),
            const SizedBox(height: Espace.sm),
            if (ventes.isEmpty)
              const EtatVide(
                icone: Icons.shopping_cart_outlined,
                message: 'Aucune vente enregistrée',
                description:
                    'Les achats effectués par ce client s\'afficheront ici.',
              )
            else
              AppCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...ventes.take(10).map((v) => Column(
                          children: [
                            ListTile(
                              dense: true,
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  showDragHandle: false,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => VenteDetailSheet(vente: v),
                                );
                              },
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(Rayon.sm),
                                ),
                                child: Icon(Icons.receipt_rounded,
                                    size: 18, color: scheme.primary),
                              ),
                              title: Text(
                                v.numero.isEmpty ? 'En attente…' : v.numero,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                fmtDateCourtIso(v.date),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    fmtGNF(v.totalNet),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 18, color: scheme.outline),
                                ],
                              ),
                            ),
                            if (v != ventes.take(10).last)
                              const Divider(height: 1),
                          ],
                        )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _lancerAppel(String tel) async {
    final cleaned = tel.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Erreur lors du lancement de l\'appel: $e');
    }
  }

  void _lancerWhatsApp(BuildContext context, String tel) async {
    if (tel.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun numéro de téléphone disponible.')),
      );
      return;
    }

    // Extraction des chiffres uniquement pour wa.me (sans le + ou caractères spéciaux)
    String cleaned = tel.replaceAll(RegExp(r'[^\d]'), '');

    // Suppression des zéros initiaux si code international saisi avec 00
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith('0') && cleaned.length == 10) {
      cleaned = cleaned.substring(1);
    }

    // Si le numéro fait 9 chiffres (format local Guinée ex: 620XXXXXX), ajouter l'indicatif 224
    if (cleaned.length == 9) {
      cleaned = '224$cleaned';
    }

    if (cleaned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro de téléphone invalide.')),
      );
      return;
    }

    final uriNative = Uri.parse('whatsapp://send?phone=$cleaned');
    final uriWeb = Uri.parse('https://wa.me/$cleaned');

    try {
      if (await canLaunchUrl(uriNative)) {
        await launchUrl(uriNative, mode: LaunchMode.externalNonBrowserApplication);
        return;
      }
    } catch (_) {}

    try {
      if (await canLaunchUrl(uriWeb)) {
        await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    // Forcer le lancement web si canLaunchUrl renvoie false (Android 11+ query restriction)
    try {
      final launched = await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
      if (!launched) {
        final launchedNative = await launchUrl(uriNative);
        if (!launchedNative) {
          throw Exception('Impossible de lancer WhatsApp');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir WhatsApp. Assurez-vous que l\'application est installée.'),
          ),
        );
      }
    }
  }

  void _modifierClient(BuildContext context, Client client) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => ClientFormSheet(client: client),
    );
  }
}

class _InfoRowTile extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valeur;

  const _InfoRowTile({
    required this.icone,
    required this.label,
    required this.valeur,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(Espace.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Rayon.sm),
            ),
            child: Icon(icone, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: Espace.md),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final clientStreamProvider = StreamProvider.family<Client?, String>((ref, id) {
  final stores = ref.watch(storesProvider);
  return stores.watchClients().map((clients) {
    try {
      return clients.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  });
});
