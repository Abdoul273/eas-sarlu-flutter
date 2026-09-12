import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../app/format.dart';
import '../../app/ui_kit.dart';
import '../../app/theme.dart';
import '../../core/db/stores.dart';
import '../../core/finance/regles_vente.dart';
import '../../core/models/models.dart';
import '../../core/sync/op_queue.dart';
import '../dashboard/dashboard_page.dart';
import 'ventes_page.dart';

// Modèle pour une ligne du panier (local)
class LignePanier {
  final String id;
  Article article;
  int quantite;
  int prixUnitaire;

  LignePanier({
    required this.id,
    required this.article,
    this.quantite = 1,
    required this.prixUnitaire,
  });

  int get total => quantite * prixUnitaire;
}

/// Ouvre la modification d'une vente à partir de son seul identifiant.
///
/// La route passait la vente entière dans `extra` et la lisait par un `as
/// Vente` sec. Tout ce qui atteint l'écran sans passer par le bouton — lien
/// direct, retour arrière, redémarrage à chaud, clic sur une notification —
/// arrive sans `extra` et faisait alors tomber l'application sur un écran
/// rouge. L'identifiant, lui, est toujours dans l'URL.
class ModifierVenteParId extends ConsumerWidget {
  const ModifierVenteParId({super.key, required this.venteId, this.vente});

  final String venteId;

  /// La vente déjà en main, quand l'écran précédent l'avait ; évite un
  /// clignotement de chargement dans le cas courant.
  final Vente? vente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (vente != null) return ModifierVentePage(venteInitiale: vente!);

    return FutureBuilder<Vente?>(
      future: ref.read(storesProvider).getVente(venteId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final trouvee = snapshot.data;
        if (trouvee == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Modifier la vente')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(Espace.xl),
                child: Text(
                  'Cette vente est introuvable sur cet appareil.\n'
                  'Synchronisez, puis réessayez.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return ModifierVentePage(venteInitiale: trouvee);
      },
    );
  }
}

class ModifierVentePage extends ConsumerStatefulWidget {
  final Vente venteInitiale;

  const ModifierVentePage({
    super.key,
    required this.venteInitiale,
  });

  @override
  ConsumerState<ModifierVentePage> createState() => _ModifierVentePageState();
}

class _ModifierVentePageState extends ConsumerState<ModifierVentePage> {
  final _clientController = TextEditingController();
  final _articleController = TextEditingController();
  Client? _clientSelectionne;
  String _clientQuery = '';
  String _articleQuery = '';
  final List<LignePanier> _panier = [];
  final _uuid = const Uuid();

  /// Empêche un second envoi tant que le premier n'est pas terminé. Sans lui,
  /// un double appui sur « Enregistrer » déposait DEUX modifications dans la
  /// file, et le stock encaissait deux fois le même écart.
  bool _envoiEnCours = false;

  /// Quantités déjà sorties du stock par la vente en cours de modification,
  /// article par article.
  ///
  /// Elles sont indispensables au calcul du disponible : le stock affiché tient
  /// déjà compte de cette vente. Sans ce crédit, une vente qui a vidé le stock
  /// d'un article rendait cet article impossible à conserver dans sa propre
  /// modification — la quantité retombait silencieusement à 1.
  final Map<String, int> _dejaSorti = {};

  @override
  void initState() {
    super.initState();
    for (final l in widget.venteInitiale.lignes) {
      _dejaSorti[l.articleId] = (_dejaSorti[l.articleId] ?? 0) + l.qte;
    }
    _clientController.addListener(
        () => setState(() => _clientQuery = _clientController.text.trim()));
    _articleController.addListener(
        () => setState(() => _articleQuery = _articleController.text.trim()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _preremplir());
  }

  Future<void> _preremplir() async {
    final stores = ref.read(storesProvider);

    if (widget.venteInitiale.clientId.isNotEmpty) {
      final client = await stores.getClient(widget.venteInitiale.clientId);
      if (client != null && mounted) _choisirClient(client);
    }

    for (final ligne in widget.venteInitiale.lignes) {
      // Un article disparu du catalogue est reconstitué à partir de la ligne de
      // vente : sans cela, modifier une vente ancienne perdait ses lignes.
      final article = await stores.getArticle(ligne.articleId) ??
          Article(
            id: ligne.articleId,
            ref: ligne.articleRef,
            nom: ligne.articleNom,
            categorie: 'Inconnu',
            description: 'Article supprimé ou non synchronisé',
            unite: ligne.unite,
            prixAchat: 0,
            prixVente: ligne.prixUnitaire,
            stock: 0,
            stockMin: 0,
          );
      if (!mounted) return;
      setState(() {
        _panier.add(LignePanier(
          id: _uuid.v4(),
          article: article,
          quantite: ligne.qte,
          prixUnitaire: ligne.prixUnitaire,
        ));
      });
    }
  }

  @override
  void dispose() {
    _clientController.dispose();
    _articleController.dispose();
    super.dispose();
  }

  /// Ce qu'il reste à prendre pour cet article, dans le contexte d'une
  /// MODIFICATION.
  ///
  /// Le stock enregistré tient déjà compte des quantités que cette vente a
  /// sorties : on les remet donc au pot avant de retrancher le panier en cours.
  /// Sans ce crédit, modifier une vente qui avait vidé le stock d'un article
  /// ramenait sa quantité à 1 sans rien dire, et la correction sortait du
  /// magasin de la marchandise qu'il n'avait jamais eue.
  int stockDisponible(Article article) {
    final creditVenteEnCours = _dejaSorti[article.id] ?? 0;
    final reserve = _panier
        .where((l) => l.article.id == article.id)
        .fold<int>(0, (sum, l) => sum + l.quantite);
    return article.stock + creditVenteEnCours - reserve;
  }

  void _ajouterAuPanier(Article article) {
    if (stockDisponible(article) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock insuffisant pour ${article.nom}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() {
      // Un article déjà au panier se cumule sur sa ligne : une seule ligne
      // par article, comme à la création d'une vente.
      final existante =
          _panier.where((l) => l.article.id == article.id).firstOrNull;
      if (existante != null) {
        existante.quantite += 1;
      } else {
        _panier.add(LignePanier(
          id: _uuid.v4(),
          article: article,
          prixUnitaire: article.prixVente,
        ));
      }
      _articleController.clear();
      _articleQuery = '';
    });
    HapticFeedback.lightImpact();
  }

  void _supprimerLigne(String id) {
    setState(() => _panier.removeWhere((l) => l.id == id));
  }

  void _updateQuantite(LignePanier ligne, int qte) {
    final stockMax = stockDisponible(ligne.article) + ligne.quantite;
    if (stockMax <= 0) {
      _avertir('${ligne.article.nom} : plus rien en stock.');
      _supprimerLigne(ligne.id);
      return;
    }
    final qteValide = qte.clamp(1, stockMax);
    if (qte > stockMax) {
      _avertir('Quantité limitée au stock disponible '
          '(${fmtNombre(stockMax)} ${ligne.article.unite})');
    }
    setState(() => ligne.quantite = qteValide);
  }

  void _updatePrix(LignePanier ligne, int prix) {
    setState(() => ligne.prixUnitaire = prix);
  }

  void _avertir(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<void> _encaisser() async {
    if (_envoiEnCours) return;
    if (_panier.isEmpty) {
      _avertir('Le panier est vide');
      return;
    }

    setState(() => _envoiEnCours = true);
    try {
      await _enregistrerModification();
    } catch (e) {
      // Une erreur silencieuse sur une modification de vente, c'est un écran
      // qui laisse croire que tout est enregistré alors que rien ne l'est.
      if (mounted) _avertir('Modification non enregistrée : $e');
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  Future<void> _enregistrerModification() async {
    final stores = ref.read(storesProvider);
    final opQueue = ref.read(opQueueProvider);

    final lignes = _panier
        .map((l) => LigneVente(
              articleId: l.article.id,
              articleRef: l.article.ref,
              articleNom: l.article.nom,
              unite: l.article.unite,
              qte: l.quantite,
              prixUnitaire: l.prixUnitaire,
              remise: 0,
              total: l.total,
              // Une ligne conservée garde son prix d'achat d'origine ; une
              // ligne ajoutée prend celui du jour.
              prixAchat: widget.venteInitiale.lignes
                      .where((o) => o.articleId == l.article.id)
                      .firstOrNull
                      ?.prixAchat ??
                  l.article.prixAchat,
            ))
        .toList();

    final totalNet = lignes.fold<int>(0, (sum, l) => sum + l.total);

    // La facture porte les versements : c'est elle qui dit si la modification
    // est recevable. Lecture ponctuelle, et non `watchFactures().first` : cette
    // dernière ouvrait un flux drift qu'aucun code ne refermait.
    final factures = await stores.getFactures();
    Facture? factureLiee;
    for (final f in factures) {
      if (f.venteId == widget.venteInitiale.id) {
        factureLiee = f;
        break;
      }
    }

    // On ne descend jamais une vente sous ce qui a déjà été encaissé dessus :
    // le magasin se retrouverait débiteur de son propre client sans que
    // personne ne l'ait décidé. Le serveur applique la même règle — celle-ci
    // n'est là que pour l'expliquer avant l'envoi plutôt qu'après.
    if (factureLiee != null) {
      final encaisse = montantPaye(factureLiee);
      if (encaisse > totalNet) {
        _avertir(
            'Cette vente a déjà été réglée à hauteur de ${fmtGNF(encaisse)}. '
            'Annulez d\'abord le versement pour la ramener à ${fmtGNF(totalNet)}.');
        return;
      }
    }

    // Écarts de stock : quantité voulue moins quantité déjà sortie. Positif, la
    // marchandise sort ; négatif, elle rentre.
    final deltas = <String, int>{};
    for (final ancienne in widget.venteInitiale.lignes) {
      deltas[ancienne.articleId] =
          (deltas[ancienne.articleId] ?? 0) - ancienne.qte;
    }
    for (final nouvelle in _panier) {
      deltas[nouvelle.article.id] =
          (deltas[nouvelle.article.id] ?? 0) + nouvelle.quantite;
    }

    // Dernier rempart, sur les stocks relus à l'instant : ce que la vente
    // avait sorti revient au pot, puis on vérifie que le nouveau panier tient.
    final frais = <String, Article>{};
    for (final id in deltas.keys) {
      final a = await stores.getArticle(id);
      if (a != null) frais[id] = a;
    }
    final problemes = problemesVente(
      [for (final l in _panier) DemandeLigne(l.article.id, l.quantite, l.prixUnitaire)],
      frais,
      credit: _dejaSorti,
    );
    if (problemes.isNotEmpty) {
      setState(() {
        for (final l in _panier) {
          final a = frais[l.article.id];
          if (a != null) l.article = a;
        }
      });
      _avertir(problemes.map((p) => p.message).join('\n'));
      return;
    }

    // Les lignes sont reconstruites sans remise, et le total est leur somme :
    // une remise globale héritée d'une vente faite au navigateur ne doit pas
    // rester écrite alors que le total ne l'applique plus.
    final venteMaj = widget.venteInitiale.copyWith(
      clientId: _clientSelectionne?.id ?? '',
      lignes: lignes,
      remiseGlobale: 0,
      totalHT: totalNet,
      totalNet: totalNet,
    );

    await stores.transaction(() async {
      for (final entree in deltas.entries) {
        if (entree.value == 0) continue;
        final article = frais[entree.key];
        if (article == null) continue;
        final stock = entree.value > 0
            ? stockApresSortie(article.stock, entree.value)
            : stockApresRetour(article.stock, -entree.value);
        await stores.upsert('article', article.copyWith(stock: stock));
      }
      await stores.upsert('vente', venteMaj);
      if (factureLiee != null) {
        await stores.upsert(
          'facture',
          factureLiee.copyWith(
            clientId: _clientSelectionne?.id ?? '',
            montantHT: totalNet,
            montantTTC: totalNet,
            remise: 0,
          ),
        );
      }
    });

    // Opération DÉDIÉE, et non « vente ».
    //
    // Renvoyée comme une vente, la modification était traitée par le serveur
    // comme une vente neuve : nouveau numéro VTE et FAC, stock redéduit une
    // seconde fois — y compris quand on RÉDUISAIT la vente — et écriture
    // rejetée en silence puisque l'identifiant existait déjà. La correction
    // disparaissait au premier instantané suivant, en laissant le stock faux.
    //
    // Les écarts ne sont volontairement pas transmis : le serveur les recalcule
    // d'après la vente enregistrée. Ceux calculés ici valent pour l'état que ce
    // téléphone connaît, qui peut dater d'avant la dernière synchronisation.
    await opQueue.enqueue('vente_modification', {
      'venteId': widget.venteInitiale.id,
      'lignes': lignes.map((l) => l.toJson()).toList(),
      'clientId': _clientSelectionne?.id ?? '',
      if (widget.venteInitiale.rev != null) 'baseRev': widget.venteInitiale.rev,
      if (factureLiee != null) 'factureId': factureLiee.id,
    });

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _showConfirmation(factureLiee?.id ?? '');
  }

  void _showConfirmation(String factureId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.xl)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Vente modifiée !'),
          ],
        ),
        content: const Text(
          'La vente et la facture correspondante ont été mises à jour avec succès.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Retour'),
          ),
          if (factureId.isNotEmpty)
            AppButton(
              label: 'Consulter la facture',
              icon: Icons.receipt_long_rounded,
              onPressed: () {
                Navigator.pop(ctx);
                context.pushReplacementNamed('detail-facture',
                    pathParameters: {'id': factureId});
              },
            ),
        ],
      ),
    );
  }

  void _choisirClient(Client? client) {
    setState(() {
      _clientSelectionne = client;
      _clientController.text = client?.nom ?? '';
      _clientQuery = '';
    });
  }

  void _creerClientRapide() {
    final nomCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.xl)),
        title: const Text('Nouveau Client Rapide'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom du client *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: Espace.md),
            TextField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          AppButton(
            label: 'Enregistrer',
            icon: Icons.check_rounded,
            onPressed: () async {
              if (nomCtrl.text.trim().isEmpty) return;
              final client = Client(
                id: _uuid.v4(),
                nom: nomCtrl.text.trim(),
                telephone: telCtrl.text.trim(),
                creeLe: DateTime.now().toIso8601String(),
              );
              final stores = ref.read(storesProvider);
              final opQueue = ref.read(opQueueProvider);
              await stores.upsert('client', client);
              await opQueue.enqueue('client', {'record': client.toJson()});
              if (!mounted) return;
              _choisirClient(client);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final articles = ref.watch(tousArticlesProvider).valueOrNull ?? [];
    final clients = ref.watch(tousClientsProvider).valueOrNull ?? [];

    final articlesFiltres = _articleQuery.isEmpty
        ? <Article>[]
        : articles
            .where((a) =>
                a.nom.toLowerCase().contains(_articleQuery.toLowerCase()) ||
                a.ref.toLowerCase().contains(_articleQuery.toLowerCase()))
            .toList();

    final clientsFiltres = _clientQuery.isEmpty
        ? <Client>[]
        : clients
            .where(
                (c) => c.nom.toLowerCase().contains(_clientQuery.toLowerCase()))
            .toList();

    final totalHT = _panier.fold<int>(0, (sum, l) => sum + l.total);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Modifier Vente',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Caisse & Panier d\'encaissement',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_panier.isNotEmpty)
            IconButton(
              tooltip: 'Vider le panier',
              icon: Icon(Icons.delete_sweep_rounded, color: scheme.error),
              onPressed: () {
                setState(() => _panier.clear());
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Section Client & Recherche Article Card
          Padding(
            padding: const EdgeInsets.all(Espace.page),
            child: Column(
              children: [
                // Client Card Selector
                _buildClientSelector(theme, scheme, clientsFiltres),
                const SizedBox(height: Espace.md),

                // Article Search Field
                TextField(
                  controller: _articleController,
                  decoration: InputDecoration(
                    labelText: 'Rechercher un article (nom, réf)...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _articleQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _articleController.clear();
                              setState(() => _articleQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),

          // Search Suggestions Layer
          if (_articleQuery.isNotEmpty)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: Espace.page),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(Rayon.md),
                  border: Border.all(color: scheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: articlesFiltres.isEmpty
                    ? const EtatVide(
                        icone: Icons.search_off_rounded,
                        message: 'Aucun article trouvé',
                        compact: true,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(Espace.xs),
                        itemCount: articlesFiltres.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final a = articlesFiltres[index];
                          final dispo = stockDisponible(a);
                          final aEnStock = dispo > 0;

                          return ListTile(
                            title: Text(
                              a.nom,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: aEnStock ? scheme.onSurface : scheme.onSurfaceVariant,
                              ),
                            ),
                            subtitle: Text(
                              '${fmtGNF(a.prixVente)} / ${a.unite} • ${aEnStock ? '$dispo ${a.unite} dispo.' : 'Rupture'}',
                              style: TextStyle(
                                color: aEnStock ? scheme.onSurfaceVariant : scheme.error,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.add_circle_rounded,
                                color: aEnStock ? scheme.primary : scheme.outlineVariant,
                                size: 28,
                              ),
                              onPressed: aEnStock ? () => _ajouterAuPanier(a) : null,
                            ),
                            onTap: aEnStock ? () => _ajouterAuPanier(a) : null,
                          );
                        },
                      ),
              ),
            )
          else
            // Panier Items List
            Expanded(
              child: _panier.isEmpty
                  ? const EtatVide(
                      icone: Icons.shopping_cart_outlined,
                      message: 'Le panier est vide',
                      description: 'Recherchez un article ci-dessus pour l\'ajouter à la vente.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                      itemCount: _panier.length,
                      itemBuilder: (context, index) {
                        final ligne = _panier[index];
                        final dispo = stockDisponible(ligne.article);
                        return _LignePanierWidget(
                          key: ValueKey(ligne.id),
                          ligne: ligne,
                          stockMax: dispo + ligne.quantite,
                          onQuantiteChanged: (qte) => _updateQuantite(ligne, qte),
                          onPrixChanged: (p) => _updatePrix(ligne, p),
                          onDelete: () => _supprimerLigne(ligne.id),
                        );
                      },
                    ),
            ),

          // Bottom Sticky Checkout Bar
          Container(
            padding: const EdgeInsets.all(Espace.page),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              border: Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Total (${_panier.length} article${_panier.length > 1 ? 's' : ''})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: Espace.sm),
                      Text(
                        fmtGNF(totalHT),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espace.md),
                  AppButton(
                    label: _envoiEnCours
                        ? 'Enregistrement…'
                        : 'Mettre à jour (${fmtGNF(totalHT)})',
                    icon: Icons.point_of_sale_rounded,
                    expanded: true,
                    onPressed: _panier.isNotEmpty && !_envoiEnCours
                        ? _encaisser
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientSelector(ThemeData theme, ColorScheme scheme, List<Client> clientsFiltres) {
    final clientActuel = _clientSelectionne;

    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(Espace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Rayon.sm),
                ),
                child: Icon(Icons.person_pin_rounded, color: scheme.primary, size: 20),
              ),
              const SizedBox(width: Espace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientActuel != null ? clientActuel.nom : 'Client de passage',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      clientActuel != null
                          ? (clientActuel.telephone.isNotEmpty ? clientActuel.telephone : 'Client enregistré')
                          : 'Vente directe au comptoir',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (clientActuel != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Réinitialiser client',
                  onPressed: () => _choisirClient(null),
                )
              else
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
                  tooltip: 'Créer un client',
                  onPressed: _creerClientRapide,
                ),
            ],
          ),
          if (clientActuel == null) ...[
            const SizedBox(height: Espace.sm),
            TextField(
              controller: _clientController,
              decoration: const InputDecoration(
                hintText: 'Rechercher un client existant...',
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            if (_clientQuery.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                margin: const EdgeInsets.only(top: Espace.xs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(Rayon.md),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...clientsFiltres.map((c) => ListTile(
                          dense: true,
                          title: Text(c.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(c.telephone),
                          onTap: () => _choisirClient(c),
                        )),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline_rounded, size: 18),
                      title: const Text('Garder "Client de passage"'),
                      onTap: () => _choisirClient(null),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// Widget pour une ligne du panier avec saisie directe de la quantité
class _LignePanierWidget extends StatefulWidget {
  final LignePanier ligne;
  final int stockMax;
  final ValueChanged<int> onQuantiteChanged;
  final ValueChanged<int> onPrixChanged;
  final VoidCallback onDelete;

  const _LignePanierWidget({
    super.key,
    required this.ligne,
    required this.stockMax,
    required this.onQuantiteChanged,
    required this.onPrixChanged,
    required this.onDelete,
  });

  @override
  State<_LignePanierWidget> createState() => _LignePanierWidgetState();
}

class _LignePanierWidgetState extends State<_LignePanierWidget> {
  late TextEditingController _qteCtrl;
  late TextEditingController _prixCtrl;

  @override
  void initState() {
    super.initState();
    _qteCtrl = TextEditingController(text: widget.ligne.quantite.toString());
    _prixCtrl = TextEditingController(text: widget.ligne.prixUnitaire.toString());
    _qteCtrl.addListener(_onQteTextChanged);
    _prixCtrl.addListener(_onPrixTextChanged);
  }

  void _onQteTextChanged() {
    final val = parseMontantClean(_qteCtrl.text);
    if (val > 0) {
      widget.onQuantiteChanged(val);
    }
  }

  void _onPrixTextChanged() {
    final val = parseMontantClean(_prixCtrl.text);
    widget.onPrixChanged(val);
  }

  @override
  void didUpdateWidget(covariant _LignePanierWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ligne.quantite != oldWidget.ligne.quantite &&
        _qteCtrl.text != widget.ligne.quantite.toString()) {
      _qteCtrl.text = widget.ligne.quantite.toString();
    }
    if (widget.ligne.prixUnitaire != oldWidget.ligne.prixUnitaire &&
        _prixCtrl.text != widget.ligne.prixUnitaire.toString()) {
      _prixCtrl.text = widget.ligne.prixUnitaire.toString();
    }
  }

  @override
  void dispose() {
    _qteCtrl.removeListener(_onQteTextChanged);
    _prixCtrl.removeListener(_onPrixTextChanged);
    _qteCtrl.dispose();
    _prixCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ligne = widget.ligne;

    return Dismissible(
      key: Key(ligne.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(Rayon.md),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
      child: AppCard(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(Espace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    ligne.article.nom,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            const SizedBox(height: Espace.xs),
            Row(
              children: [
                // Field for typing Quantity directly
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _qteCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Qté *',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const Spacer(),
                // Unit Price Field
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _prixCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      labelText: 'Prix unit.',
                      isDense: true,
                      suffixText: 'GNF',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espace.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${fmtGNF(ligne.total)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
