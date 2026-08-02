import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../dashboard/dashboard_page.dart';
import 'ventes_page.dart';

final factureParVenteIdProvider =
    StreamProvider.family<Facture?, String>((ref, venteId) {
  final stores = ref.watch(storesProvider);
  return stores.watchFactures().map((factures) {
    try {
      return factures.firstWhere((f) => f.venteId == venteId);
    } catch (_) {
      return null;
    }
  });
});

class VenteDetailSheet extends ConsumerWidget {
  final Vente vente;
  const VenteDetailSheet({super.key, required this.vente});

  String _fmt(WidgetRef ref, int montant) {
    final masque = ref.watch(masquerMontantsProvider);
    return masque ? '•••• GNF' : fmtGNF(montant);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metier = context.metier;
    final factureAsync = ref.watch(factureParVenteIdProvider(vente.id));
    final facture = factureAsync.valueOrNull;
    final clientMap = ref.watch(clientMapProvider);
    final client = clientMap[vente.clientId];
    final clientNom = client?.nom ??
        (vente.clientId.isEmpty ? 'Client de passage' : vente.clientId);
    final enAttente = vente.numero.isEmpty;
    final numero = enAttente ? 'Vente en attente…' : 'Vente N° ${vente.numero}';
    final totalPaye = facture?.paiements.fold<int>(0, (sum, p) => sum + p.montant) ?? 0;
    final bool estPayee = facture != null && totalPaye >= facture.montantTTC;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: Rayon.feuille,
          ),
          child: Column(
            children: [
              const PoigneeFeuille(),

              // En-tête Vente Banner Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                child: Container(
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
                          color: enAttente
                              ? metier.alerte.withValues(alpha: 0.14)
                              : scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Rayon.md),
                        ),
                        child: Icon(
                          enAttente
                              ? Icons.hourglass_top_rounded
                              : Icons.point_of_sale_rounded,
                          size: 26,
                          color: enAttente ? metier.alerte : scheme.primary,
                        ),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              numero,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            if (facture != null)
                              BadgePastille(
                                texte: 'Facturée (${facture.numero})',
                                couleur: metier.succes,
                                icone: Icons.check_circle_rounded,
                              )
                            else if (enAttente)
                              BadgePastille(
                                texte: 'En attente de synchro',
                                couleur: metier.alerte,
                                icone: Icons.sync_rounded,
                              )
                            else
                              BadgePastille(
                                texte: 'Vente effectuée',
                                couleur: scheme.primary,
                                icone: Icons.shopping_bag_rounded,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Espace.md),

              // Contenu défilable
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Meta Info (Client, Vendeur, Date)
                      AppCard(
                        margin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            _InfoLine(
                              icone: Icons.person_rounded,
                              label: 'Client',
                              valeur: clientNom,
                              couleurIcone: scheme.primary,
                            ),
                            const Divider(height: 16),
                            _InfoLine(
                              icone: Icons.badge_rounded,
                              label: 'Vendeur',
                              valeur: vente.vendeur.isNotEmpty
                                  ? vente.vendeur
                                  : 'Non spécifié',
                              couleurIcone: metier.info,
                            ),
                            const Divider(height: 16),
                            _InfoLine(
                              icone: Icons.access_time_rounded,
                              label: 'Date & heure',
                              couleurIcone: scheme.secondary,
                              customValeur: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(Rayon.sm),
                                  border: Border.all(
                                    color: scheme.secondary
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 14,
                                      color: scheme.secondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      fmtDateHeureExacteIso(vente.date),
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: scheme.onSurface,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (vente.note.isNotEmpty) ...[
                              const Divider(height: 16),
                              _InfoLine(
                                icone: Icons.notes_rounded,
                                label: 'Note',
                                valeur: vente.note,
                                couleurIcone: metier.alerte,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: Espace.lg),

                      // Articles vendus Header
                      Text(
                        'Articles vendus (${vente.lignes.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: Espace.xs),

                      // Liste des lignes de vente
                      AppCard(
                        margin: EdgeInsets.zero,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (int i = 0; i < vente.lignes.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _LigneVenteItem(
                                ligne: vente.lignes[i],
                                ref: ref,
                                fmt: _fmt,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: Espace.lg),

                      // Carte Résumé Financier
                      Container(
                        padding: const EdgeInsets.all(Espace.md),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(Rayon.lg),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Net à payer',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _fmt(ref, vente.totalNet),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Espace.xl),
                    ],
                  ),
                ),
              ),

              // Bottom Action Button
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(Espace.page),
                  child: Column(
                    children: [
                      if (facture != null) ...[
                        AppButton(
                          label: 'Consulter la facture (${facture.numero})',
                          icon: Icons.receipt_long_rounded,
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).pop();
                            context.pushNamed('detail-facture',
                                pathParameters: {'id': facture.id});
                          },
                          expanded: true,
                        ),
                        const SizedBox(height: Espace.md),
                      ],
                      if (!estPayee)
                        AppButton(
                          label: 'Modifier la vente',
                          icon: Icons.edit_rounded,
                          onPressed: () {
                            final router = GoRouter.of(context);
                            Navigator.of(context, rootNavigator: true).pop();
                            router.pushNamed('modifier-vente',
                                pathParameters: {'id': vente.id}, extra: vente);
                          },
                          expanded: true,
                        ),
                    ],
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

class _InfoLine extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valeur;
  final Color couleurIcone;
  final Widget? customValeur;

  const _InfoLine({
    required this.icone,
    required this.label,
    this.valeur = '',
    required this.couleurIcone,
    this.customValeur,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: couleurIcone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Rayon.sm),
          ),
          child: Icon(icone, size: 16, color: couleurIcone),
        ),
        const SizedBox(width: Espace.sm),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (customValeur != null)
          customValeur!
        else
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
    );
  }
}

class _LigneVenteItem extends StatelessWidget {
  final LigneVente ligne;
  final WidgetRef ref;
  final String Function(WidgetRef, int) fmt;

  const _LigneVenteItem({
    required this.ligne,
    required this.ref,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(Espace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ligne.articleNom,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ligne.articleRef.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      BadgePastille(
                        texte: ligne.articleRef,
                        couleur: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${ligne.qte} x ${fmt(ref, ligne.prixUnitaire)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Espace.sm),
          Text(
            fmt(ref, ligne.total),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
