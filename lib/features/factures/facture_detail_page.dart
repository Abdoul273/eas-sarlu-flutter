import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../ventes/ventes_page.dart'; // clientMapProvider, entrepriseProvider
import 'paiement_sheet.dart';
import 'facture_pdf.dart';
import '../../core/reseau.dart';

// Provider pour obtenir la vente liée à une facture
final venteParIdProvider =
    FutureProvider.family<Vente?, String>((ref, venteId) async {
  final stores = ref.read(storesProvider);
  return stores.getVente(venteId);
});

class FactureDetailPage extends ConsumerWidget {
  final String id;
  const FactureDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factureAsync = ref.watch(factureStreamProvider(id));
    return factureAsync.when(
      data: (facture) {
        if (facture == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EtatVide(message: 'Facture introuvable'),
          );
        }
        return _FactureDetailBody(facture: facture);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Erreur: $e'))),
    );
  }
}

class _FactureDetailBody extends ConsumerWidget {
  final Facture facture;
  const _FactureDetailBody({required this.facture});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientMap = ref.watch(clientMapProvider);
    final client = clientMap[facture.clientId];
    final entrepriseAsync = ref.watch(entrepriseProvider);
    final venteAsync = ref.watch(venteParIdProvider(facture.venteId));
    final paiements = facture.paiements;
    final paye = montantPaye(facture);
    final reste = resteDu(facture);
    final estPayee = reste <= 0;
    final progression =
        facture.montantTTC > 0 ? (paye / facture.montantTTC).clamp(0.0, 1.0) : 0.0;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;
    final couleurStatut = estPayee
        ? metier.succes
        : (paye > 0 ? metier.alerte : metier.danger);
    final texteStatut = estPayee
        ? 'Payée'
        : (paye > 0 ? 'Paiement partiel' : 'Impayée');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Facture ${facture.numero}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Émise le ${fmtDateCourtIso(facture.dateEmission)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Générer PDF',
            onPressed: () => _partagerPdf(context, ref, facture,
                venteAsync.value, client, entrepriseAsync.valueOrNull),
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Imprimer',
            onPressed: () => _imprimer(context, ref, facture,
                venteAsync.value, client, entrepriseAsync.valueOrNull),
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
            // Carte Header Banner
            AppCard(
              margin: EdgeInsets.zero,
              accent: couleurStatut,
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(Espace.md),
                        decoration: BoxDecoration(
                          color: couleurStatut.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Rayon.md),
                        ),
                        child: Icon(
                          estPayee
                              ? Icons.verified_rounded
                              : Icons.receipt_long_rounded,
                          color: couleurStatut,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              facture.numero,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            BadgePastille(
                              texte: texteStatut,
                              couleur: couleurStatut,
                              icone: estPayee
                                  ? Icons.check_circle_rounded
                                  : Icons.hourglass_top_rounded,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Montant Total',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              fmtGNF(facture.montantTTC),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Client & Entreprise Info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CLIENT',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              client?.nom ?? 'Client de passage',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (client != null && client.telephone.isNotEmpty)
                              Text(
                                client.telephone,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            if (client != null && client.adresse.isNotEmpty)
                              Text(
                                client.adresse,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: Espace.md),
                        color: scheme.outlineVariant,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ÉMETTEUR',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entrepriseAsync.value?.nom ?? 'E.A.S Sarlu',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (entrepriseAsync.value?.telephone.isNotEmpty ?? false)
                              Text(
                                entrepriseAsync.value!.telephone,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            // Barre de progression du Règlement
            const SectionHeader(
              titre: 'Règlement & Progression',
              icone: Icons.account_balance_wallet_rounded,
            ),
            const SizedBox(height: Espace.sm),
            AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Paiement effectué',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${(progression * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: couleurStatut,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espace.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Rayon.pilule),
                    child: LinearProgressIndicator(
                      value: progression,
                      minHeight: 10,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: couleurStatut,
                    ),
                  ),
                  const SizedBox(height: Espace.sm + 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Encaissé : ${fmtGNF(paye)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: metier.succes,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        reste > 0 ? 'Reste dû : ${fmtGNF(reste)}' : 'Intégralement payé',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: reste > 0 ? metier.danger : metier.succes,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Espace.lg),

            // Lignes de la Vente
            if (venteAsync.value != null) ...[
              const SectionHeader(
                titre: 'Articles & Décompte',
                icone: Icons.shopping_bag_rounded,
              ),
              const SizedBox(height: Espace.sm),
              AppCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...venteAsync.value!.lignes.map(
                      (l) => Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(Espace.md),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(Rayon.sm),
                                  ),
                                  child: Icon(Icons.inventory_2_rounded,
                                      size: 18, color: scheme.primary),
                                ),
                                const SizedBox(width: Espace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.articleNom,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Réf: ${l.articleRef} • ${l.qte} x ${fmtGNF(l.prixUnitaire)}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      fmtGNF(l.total),
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Espace.md),
                      child: Column(
                        children: [
                          _buildTotalRow('Total à payer', facture.montantTTC,
                              bold: true, couleur: scheme.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.lg),
            ],

            // Historique des Versements
            const SectionHeader(
              titre: 'Historique des Versements',
              icone: Icons.history_rounded,
            ),
            const SizedBox(height: Espace.sm),
            if (paiements.isEmpty)
              const EtatVide(
                icone: Icons.payments_outlined,
                message: 'Aucun versement enregistré',
                description:
                    'Cliquez sur le bouton ci-dessous pour encaisser un versement.',
              )
            else
              AppCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...paiements.map(
                      (p) => Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(Espace.md),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: metier.succes.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(Rayon.sm),
                                  ),
                                  child: Icon(
                                    p.mode.toLowerCase().contains('mobile')
                                        ? Icons.phone_android_rounded
                                        : Icons.payments_rounded,
                                    size: 18,
                                    color: metier.succes,
                                  ),
                                ),
                                const SizedBox(width: Espace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fmtGNF(p.montant),
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: metier.succes,
                                        ),
                                      ),
                                      Text(
                                        'Règlement en ${p.mode} ${p.utilisateur.isNotEmpty ? 'par ${p.utilisateur}' : ''}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        fmtDateIso(p.date),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: scheme.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded,
                                      size: 20, color: metier.danger),
                                  tooltip: 'Supprimer ce versement',
                                  onPressed: () =>
                                      _supprimerPaiement(context, ref, facture, p),
                                ),
                              ],
                            ),
                          ),
                          if (p != paiements.last) const Divider(height: 1),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: Espace.xl),

            // Bouton Encaisser
            if (reste > 0)
              AppButton(
                label: 'Encaisser un versement',
                icon: Icons.payments_rounded,
                onPressed: () => _encaisserVersement(context, ref, facture),
                expanded: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, int montant,
      {bool bold = false, bool isRemise = false, Color? couleur}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: couleur,
              fontSize: bold ? 16 : 14,
            ),
          ),
          Text(
            montant < 0
                ? '- ${fmtGNF(-montant)}'
                : (isRemise ? '- ${fmtGNF(montant)}' : fmtGNF(montant)),
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: isRemise ? Colors.green : couleur,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  void _encaisserVersement(
      BuildContext context, WidgetRef ref, Facture facture) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => PaiementSheet(facture: facture),
    );
  }

  void _supprimerPaiement(BuildContext context, WidgetRef ref, Facture facture,
      Paiement paiement) async {
    if (!await aUneConnexion()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connexion requise pour supprimer un versement')));
      return;
    }
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le versement'),
        content: Text(
            'Voulez-vous supprimer le versement de ${fmtGNF(paiement.montant)} effectué le ${fmtDateIso(paiement.date)} ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          AppButton(
              label: 'Supprimer',
              isDestructive: true,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.dio
            .delete('$kDataFacturePaiementDelete${facture.id}/${paiement.id}');
        final stores = ref.read(storesProvider);
        await stores.upsert(
            'facture',
            facture.copyWith(
                paiements: facture.paiements
                    .where((p) => p.id != paiement.id)
                    .toList()));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  void _partagerPdf(BuildContext context, WidgetRef ref, Facture facture,
      Vente? vente, Client? client, Entreprise? entreprise) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Génération du document PDF en cours…'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      await partagerFacturePdf(facture, vente, client, entreprise);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la génération PDF: $e')),
      );
    }
  }

  void _imprimer(BuildContext context, WidgetRef ref, Facture facture,
      Vente? vente, Client? client, Entreprise? entreprise) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Ouverture du service d\'impression…'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      await imprimerFacturePdf(facture, vente, client, entreprise);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'impression: $e')),
      );
    }
  }
}

// Provider pour obtenir une facture par ID en Stream
final factureStreamProvider =
    StreamProvider.family<Facture?, String>((ref, id) {
  final stores = ref.watch(storesProvider);
  return stores.watchFactures().map((factures) {
    try {
      return factures.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  });
});
