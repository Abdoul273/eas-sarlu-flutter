import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../../core/sync/op_queue.dart';
import '../calculateur/devis_pdf.dart';
import '../ventes/ventes_page.dart' show tousClientsProvider, entrepriseProvider;

// ─── Les proformas ────────────────────────────────────────────────────────────
// La mémoire des papiers remis. Jusqu'ici la proforma sortait du calculateur
// et disparaissait : quand le client revenait avec, on ressaisissait tout. Ici
// on la retrouve par numéro ou par nom, on la renvoie, et on la transforme en
// vente d'un geste — c'est là seulement que le stock sort.

final toutesProformasProvider = StreamProvider<List<Proforma>>((ref) {
  return ref.watch(storesProvider).watchProformas();
});

/// Filtre de la liste : tout, en cours (envoyées, acceptées), vendues, sans suite.
enum FiltreProforma { enCours, vendues, sansSuite, toutes }

class ProformasPage extends ConsumerStatefulWidget {
  const ProformasPage({super.key});

  @override
  ConsumerState<ProformasPage> createState() => _ProformasPageState();
}

class _ProformasPageState extends ConsumerState<ProformasPage> {
  final _rechercheCtrl = TextEditingController();
  String _q = '';
  FiltreProforma _filtre = FiltreProforma.enCours;

  @override
  void initState() {
    super.initState();
    _rechercheCtrl.addListener(
        () => setState(() => _q = _rechercheCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  void _retourSecurise(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/ventes');
    }
  }

  bool _passeFiltre(Proforma p) => switch (_filtre) {
        FiltreProforma.enCours => p.convertible,
        FiltreProforma.vendues => p.statut == StatutProforma.convertie,
        FiltreProforma.sansSuite => p.statut == StatutProforma.refusee,
        FiltreProforma.toutes => true,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final toutes = ref.watch(toutesProformasProvider).valueOrNull ?? const [];
    final clients = ref.watch(tousClientsProvider).valueOrNull ?? const [];
    final nomClient = {for (final c in clients) c.id: c.nom};

    final visibles = toutes.where((p) {
      if (!_passeFiltre(p)) return false;
      if (_q.isEmpty) return true;
      final nom = (nomClient[p.clientId] ?? p.clientNom).toLowerCase();
      return p.numero.toLowerCase().contains(_q) ||
          nom.contains(_q) ||
          p.lignes.any((l) => l.articleNom.toLowerCase().contains(_q));
    }).toList();

    final enCours = toutes.where((p) => p.convertible).length;
    final totalEnCours = toutes
        .where((p) => p.convertible)
        .fold<int>(0, (s, p) => s + p.totalNet);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Proformas'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
          actions: [
            IconButton(
              tooltip: 'Nouvelle proforma (calculateur)',
              icon: const Icon(Icons.calculate_outlined),
              onPressed: () => context.pushNamed('calculateur'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Espace.page, Espace.sm, Espace.page, 0),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      libelle: 'En attente',
                      valeur: '$enCours',
                      icone: Icons.hourglass_top_rounded,
                      couleurValeur: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: Espace.sm),
                  Expanded(
                    child: StatTile(
                      libelle: 'Montant en jeu',
                      valeur: fmtGNF(totalEnCours),
                      icone: Icons.request_quote_rounded,
                      couleurValeur: context.metier.info,
                    ),
                  ),
                ],
              ),
            ),
            AppSearchBar(
              controller: _rechercheCtrl,
              hintText: 'Numéro, client ou article…',
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Espace.page),
              child: Row(
                children: [
                  for (final f in FiltreProforma.values) ...[
                    ChoiceChip(
                      label: Text(switch (f) {
                        FiltreProforma.enCours => 'En cours',
                        FiltreProforma.vendues => 'Vendues',
                        FiltreProforma.sansSuite => 'Sans suite',
                        FiltreProforma.toutes => 'Toutes',
                      }),
                      selected: _filtre == f,
                      onSelected: (_) => setState(() => _filtre = f),
                    ),
                    const SizedBox(width: Espace.xs),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Espace.xs),
            Expanded(
              child: visibles.isEmpty
                  ? EtatVide(
                      icone: Icons.request_quote_outlined,
                      message: toutes.isEmpty
                          ? 'Aucune proforma'
                          : 'Rien ne correspond',
                      description: toutes.isEmpty
                          ? 'Depuis le calculateur, « Proforma » chiffre une '
                              'demande et l\'enregistre ici. Quand le client '
                              'revient, elle devient une vente en un geste.'
                          : null,
                      actionLabel: toutes.isEmpty ? 'Ouvrir le calculateur' : null,
                      onAction: toutes.isEmpty
                          ? () => context.pushNamed('calculateur')
                          : null,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(Espace.page, 0,
                          Espace.page, Espace.basDeListe),
                      itemCount: visibles.length,
                      itemBuilder: (context, i) {
                        final p = visibles[i];
                        return _TuileProforma(
                          proforma: p,
                          client: nomClient[p.clientId] ?? p.clientNom,
                          onTap: () => ouvrirDetailProforma(context, p),
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

Color _couleurStatut(BuildContext context, String statut) {
  final m = context.metier;
  final scheme = Theme.of(context).colorScheme;
  return switch (statut) {
    StatutProforma.convertie => m.succes,
    StatutProforma.acceptee => m.info,
    StatutProforma.refusee => scheme.onSurfaceVariant,
    'expire' => m.alerte,
    _ => scheme.primary,
  };
}

class _TuileProforma extends StatelessWidget {
  final Proforma proforma;
  final String client;
  final VoidCallback onTap;
  const _TuileProforma(
      {required this.proforma, required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = proforma;
    final statut = p.statutEffectif;
    final couleur = _couleurStatut(context, statut);
    final nbArticles = p.lignes.length;

    return AppCard(
      margin: const EdgeInsets.only(bottom: Espace.sm),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Rayon.md),
            ),
            child: Icon(Icons.request_quote_rounded, color: couleur),
          ),
          const SizedBox(width: Espace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.isEmpty ? 'Client de passage' : client,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.numero.isEmpty ? 'N° en attente' : p.numero} · '
                  '${fmtDateCourtIso(p.date)} · $nbArticles article${nbArticles > 1 ? 's' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: Espace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtGNF(p.totalNet),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              BadgePastille(
                texte: StatutProforma.libelle(statut),
                couleur: couleur,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Le détail ────────────────────────────────────────────────────────────────

Future<void> ouvrirDetailProforma(BuildContext context, Proforma p) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DetailProforma(id: p.id),
  );
}

class _DetailProforma extends ConsumerStatefulWidget {
  final String id;
  const _DetailProforma({required this.id});

  @override
  ConsumerState<_DetailProforma> createState() => _DetailProformaState();
}

class _DetailProformaState extends ConsumerState<_DetailProforma> {
  bool _travaille = false;

  Future<void> _changerStatut(Proforma p, String statut) async {
    final maj = p.copyWith(statut: statut);
    final stores = ref.read(storesProvider);
    await stores.upsert('devis', maj);
    await ref.read(opQueueProvider).enqueue('devis', {
      'record': maj.toJson(),
      if (p.rev != null) 'baseRev': p.rev,
    });
  }

  Future<void> _supprimer(Proforma p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette proforma ?'),
        content: Text('${p.numero} disparaîtra de la liste. Le client, lui, '
            'garde son papier.'),
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
    if (ok != true || !mounted) return;
    final stores = ref.read(storesProvider);
    await stores.supprimer('devis', p.id);
    await ref.read(opQueueProvider).enqueue('devis_delete', {'id': p.id});
    if (mounted) Navigator.pop(context);
  }

  Future<void> _agir(
      Proforma p, Future<void> Function(Devis, Entreprise?) action) async {
    if (_travaille) return;
    setState(() => _travaille = true);
    try {
      final clients = ref.read(tousClientsProvider).valueOrNull ?? const [];
      final client = clients.where((c) => c.id == p.clientId).firstOrNull;
      await action(Devis.depuisProforma(p, client: client),
          await ref.read(entrepriseProvider.future));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Impossible : $e')));
    } finally {
      if (mounted) setState(() => _travaille = false);
    }
  }

  /// La vente reprend le client et les lignes ; c'est l'écran Ventes qui
  /// confronte au stock et encaisse. Il revient marquer la proforma vendue.
  void _transformerEnVente(Proforma p) {
    Navigator.pop(context);
    context.pushNamed(
      'nouvelle-vente',
      queryParameters: {
        if (p.clientId.isNotEmpty) 'clientId': p.clientId,
        'proformaId': p.id,
      },
      extra: {
        'articles': [
          for (final l in p.lignes)
            {
              'articleId': l.articleId,
              'quantite': l.qte,
              'prixUnitaire': l.prixUnitaire,
            },
        ],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = (ref.watch(toutesProformasProvider).valueOrNull ?? const [])
        .where((x) => x.id == widget.id)
        .firstOrNull;
    if (p == null) return const SizedBox.shrink();

    final clients = ref.watch(tousClientsProvider).valueOrNull ?? const [];
    final client = clients.where((c) => c.id == p.clientId).firstOrNull;
    final nom = client?.nom ?? p.clientNom;
    final statut = p.statutEffectif;
    final couleur = _couleurStatut(context, statut);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: Rayon.feuille,
        ),
        child: Column(
          children: [
            const PoigneeFeuille(),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(
                    Espace.page, 0, Espace.page, Espace.page),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.numero.isEmpty ? 'Proforma' : p.numero,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${fmtDateCourtIso(p.date)} · valable jusqu\'au '
                              '${p.valableJusquA == null ? '—' : fmtDateCourt(p.valableJusquA!)}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      BadgePastille(
                          texte: StatutProforma.libelle(statut),
                          couleur: couleur),
                    ],
                  ),
                  const SizedBox(height: Espace.md),
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Row(
                      children: [
                        Icon(Icons.person_rounded, color: scheme.primary),
                        const SizedBox(width: Espace.sm),
                        Expanded(
                          child: Text(
                            nom.isEmpty ? 'Client de passage' : nom,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (client != null && client.telephone.isNotEmpty)
                          Text(client.telephone,
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(height: Espace.md),
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final l in p.lignes) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.articleNom,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: Espace.sm),
                              Text(
                                '${fmtNombre(l.qte)} × ${fmtNombre(l.prixUnitaire)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: Espace.sm),
                              Text(fmtGNF(l.total),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                          if (l != p.lignes.last)
                            const Divider(height: Espace.lg),
                        ],
                        const Divider(height: Espace.lg),
                        Row(
                          children: [
                            Expanded(
                              child: Text('Total',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700)),
                            ),
                            Text(fmtGNF(p.totalNet),
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: scheme.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (p.note.isNotEmpty) ...[
                    const SizedBox(height: Espace.md),
                    Text(p.note,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: Espace.lg),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Imprimer',
                          icon: Icons.print_rounded,
                          isTonal: true,
                          expanded: true,
                          loading: _travaille,
                          onPressed: () => _agir(p, imprimerDevisPdf),
                        ),
                      ),
                      const SizedBox(width: Espace.sm),
                      Expanded(
                        child: AppButton(
                          label: 'Envoyer',
                          icon: Icons.send_rounded,
                          isTonal: true,
                          expanded: true,
                          loading: _travaille,
                          onPressed: () => _agir(p, partagerDevisPdf),
                        ),
                      ),
                    ],
                  ),
                  if (p.convertible) ...[
                    const SizedBox(height: Espace.sm),
                    AppButton(
                      label: 'Transformer en vente',
                      icon: Icons.point_of_sale_rounded,
                      expanded: true,
                      onPressed: () => _transformerEnVente(p),
                    ),
                    const SizedBox(height: Espace.sm),
                    Row(
                      children: [
                        if (p.statut != StatutProforma.acceptee)
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.thumb_up_alt_outlined),
                              label: const Text('Acceptée'),
                              onPressed: () =>
                                  _changerStatut(p, StatutProforma.acceptee),
                            ),
                          ),
                        Expanded(
                          child: TextButton.icon(
                            icon: const Icon(Icons.thumb_down_alt_outlined),
                            label: const Text('Sans suite'),
                            onPressed: () =>
                                _changerStatut(p, StatutProforma.refusee),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (p.statut == StatutProforma.refusee)
                    TextButton.icon(
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Remettre en cours'),
                      onPressed: () =>
                          _changerStatut(p, StatutProforma.envoyee),
                    ),
                  if (p.statut != StatutProforma.convertie)
                    TextButton.icon(
                      icon: Icon(Icons.delete_outline_rounded,
                          color: scheme.error),
                      label: Text('Supprimer',
                          style: TextStyle(color: scheme.error)),
                      onPressed: () => _supprimer(p),
                    ),
                  if (p.statut == StatutProforma.convertie &&
                      p.venteId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Espace.sm),
                      child: Text(
                        'Vendue — la facture est dans l\'onglet Factures.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.metier.succes),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
