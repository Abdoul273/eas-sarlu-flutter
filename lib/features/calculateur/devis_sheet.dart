import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/models/models.dart';
import '../ventes/ventes_page.dart'; // tousClientsProvider, entrepriseProvider
import 'devis_pdf.dart';

// ─── Le calcul devient un papier ──────────────────────────────────────────────
// Ce qu'il manquait au calculateur : de quoi transformer un chiffrage en
// document qu'on tend au client ou qu'on lui envoie. Trois renseignements
// suffisent, et aucun n'est obligatoire — un devis doit pouvoir partir en
// quinze secondes, sinon personne ne s'en sert et le magasin continue de
// dicter les prix au téléphone.

/// Ouvre la feuille de préparation du devis.
///
/// [lignes] est le calcul en cours, déjà totalisé ligne par ligne.
Future<void> ouvrirFeuilleDevis(
  BuildContext context, {
  required List<LigneVente> lignes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FeuilleDevis(lignes: lignes),
  );
}

class FeuilleDevis extends ConsumerStatefulWidget {
  final List<LigneVente> lignes;
  const FeuilleDevis({super.key, required this.lignes});

  @override
  ConsumerState<FeuilleDevis> createState() => _FeuilleDevisState();
}

class _FeuilleDevisState extends ConsumerState<FeuilleDevis> {
  final _nomCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Client? _client;
  int _validite = kValiditeDevisJours;

  /// Le numéro est figé à l'ouverture de la feuille, et non recalculé à chaque
  /// reconstruction : sans cela, imprimer puis envoyer produisait deux
  /// documents portant deux numéros différents pour le même devis.
  late final DateTime _date = DateTime.now();
  late final String _numero = numeroDevis(_date);

  bool _travaille = false;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Devis get _devis => Devis(
        numero: _numero,
        date: _date,
        lignes: widget.lignes,
        client: _client,
        nomLibre: _nomCtrl.text,
        validiteJours: _validite,
        note: _noteCtrl.text,
      );

  Future<void> _agir(Future<void> Function(Devis, Entreprise?) action) async {
    if (_travaille) return;
    setState(() => _travaille = true);
    try {
      // La fiche est ATTENDUE, et non lue au vol.
      //
      // `entrepriseProvider` est un flux : le lire sans l'attendre rendait
      // `null` tant que la base n'avait pas répondu — c'est-à-dire toujours,
      // puisque cette feuille venait de s'ouvrir. Le devis sortait alors sans
      // logo, sans signature, sans adresse ni identifiants fiscaux, avec un
      // en-tête vide en guise d'entreprise.
      await action(_devis, await ref.read(entrepriseProvider.future));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Le devis n\'a pas pu être produit : $e')),
      );
    } finally {
      if (mounted) setState(() => _travaille = false);
    }
  }

  void _choisirClient() async {
    final clients = ref.read(tousClientsProvider).valueOrNull ?? const [];
    final rechercheCtrl = TextEditingController();

    final choisi = await showModalBottomSheet<Client?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = rechercheCtrl.text.toLowerCase().trim();
          final filtres = clients
              .where((c) =>
                  q.isEmpty ||
                  c.nom.toLowerCase().contains(q) ||
                  c.telephone.toLowerCase().contains(q))
              .toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.8,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: Rayon.feuille,
              ),
              child: Column(
                children: [
                  const PoigneeFeuille(),
                  AppSearchBar(
                    controller: rechercheCtrl,
                    hintText: 'Rechercher un client…',
                    onChanged: (_) => setSheet(() {}),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtres.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(Icons.person_outline_rounded),
                        title: Text(filtres[i].nom),
                        subtitle: filtres[i].telephone.isEmpty
                            ? null
                            : Text(filtres[i].telephone),
                        onTap: () => Navigator.pop(ctx, filtres[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (choisi != null && mounted) {
      setState(() {
        _client = choisi;
        _nomCtrl.text = choisi.nom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final devis = _devis;
    // Suivi ici pour que le flux soit ouvert avant qu'on appuie sur un bouton,
    // et pour dire à l'écran sous quelle en-tête le devis va sortir. Une fiche
    // entreprise vide se voyait jusqu'ici seulement sur le papier envoyé.
    final ent = ref.watch(entrepriseProvider).valueOrNull;
    final enTeteVide = (ent?.nom ?? '').trim().isEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: Rayon.feuille,
        ),
        child: Column(
          children: [
            const PoigneeFeuille(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(
                    Espace.page, 0, Espace.page, Espace.page),
                children: [
                  Text(
                    'Facture proforma $_numero',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${devis.lignes.length} article(s) · '
                    '${devis.totalUnites} unité(s) · ${fmtGNF(devis.total)}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Espace.sm),

                  // Sous quel en-tête le document va sortir. Un devis part chez
                  // un client : découvrir après l'envoi qu'il ne portait ni nom
                  // ni logo est trop tard.
                  Row(
                    children: [
                      Icon(
                        enTeteVide
                            ? Icons.warning_amber_rounded
                            : Icons.business_rounded,
                        size: 16,
                        color: enTeteVide
                            ? context.metier.alerte
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          enTeteVide
                              ? 'Fiche entreprise non renseignée : le devis '
                                  'sortira sans en-tête. Paramètres → Fiche '
                                  'Entreprise.'
                              : 'En-tête : ${ent!.nom}'
                                  '${ent.logo.trim().isEmpty ? ' (sans logo)' : ''}'
                                  '${ent.signatureImage.trim().isEmpty ? ', sans signature' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enTeteVide
                                ? context.metier.alerte
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espace.lg),

                  // ── Destinataire ────────────────────────────────────────
                  Text('POUR QUI',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      )),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _nomCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Nom du client (facultatif)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Choisir dans le fichier clients',
                        icon: const Icon(Icons.contacts_rounded),
                        onPressed: _choisirClient,
                      ),
                    ),
                    // Le nom tapé à la main l'emporte : on ne garde une fiche
                    // client que si son nom n'a pas été retouché ensuite.
                    onChanged: (v) => setState(() {
                      if (_client != null && v.trim() != _client!.nom) {
                        _client = null;
                      }
                    }),
                  ),
                  const SizedBox(height: Espace.md),

                  // ── Validité ────────────────────────────────────────────
                  Text('PRIX TENUS PENDANT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      )),
                  const SizedBox(height: 4),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7 j')),
                      ButtonSegment(value: 15, label: Text('15 j')),
                      ButtonSegment(value: 30, label: Text('30 j')),
                    ],
                    selected: {_validite},
                    onSelectionChanged: (v) =>
                        setState(() => _validite = v.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Valable jusqu\'au '
                    '${fmtDateNum(devis.valableJusquA.toIso8601String())}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Espace.md),

                  // ── Remarque ────────────────────────────────────────────
                  Text('REMARQUE SUR LE DEVIS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      )),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Ex. : livraison à Kipé comprise · '
                          'hors main-d\'œuvre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Espace.md),

                  // Ce qu'un devis n'est pas. Le dire ici évite qu'on le prenne
                  // pour une vente et qu'on cherche ensuite pourquoi le stock
                  // n'a pas bougé.
                  Container(
                    padding: const EdgeInsets.all(Espace.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(Rayon.sm),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: Espace.sm),
                        Expanded(
                          child: Text(
                            'Un devis n\'enregistre rien : ni vente, ni '
                            'réservation de stock. Quand le client accepte, '
                            'revenez au calculateur et créez la vente.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Actions ────────────────────────────────────────────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Espace.page),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Imprimer',
                        icon: Icons.print_rounded,
                        isTonal: true,
                        expanded: true,
                        loading: _travaille,
                        onPressed: () => _agir(imprimerDevisPdf),
                      ),
                    ),
                    const SizedBox(width: Espace.sm),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: 'Envoyer au client',
                        icon: Icons.send_rounded,
                        expanded: true,
                        loading: _travaille,
                        onPressed: () => _agir(partagerDevisPdf),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
