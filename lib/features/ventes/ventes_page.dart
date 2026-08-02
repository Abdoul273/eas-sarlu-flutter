import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../dashboard/dashboard_page.dart';
import 'vente_detail_sheet.dart';

// --- Providers locaux ---
final tousClientsProvider = StreamProvider<List<Client>>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchClients();
});

final clientMapProvider = Provider<Map<String, Client>>((ref) {
  final clients = ref.watch(tousClientsProvider).valueOrNull ?? [];
  return {for (final c in clients) c.id: c};
});

final entrepriseProvider = StreamProvider<Entreprise?>((ref) {
  final stores = ref.watch(storesProvider);
  return stores.watchEntreprise();
});

// Groupe de ventes par jour
class _GroupeVente {
  final String titre;
  final int total;
  final List<Vente> ventes;
  _GroupeVente({required this.titre, required this.total, required this.ventes});
}

final ventesGroupeesProvider = Provider<List<_GroupeVente>>((ref) {
  final ventesAsync = ref.watch(toutesVentesProvider);
  final ventes = ventesAsync.valueOrNull ?? [];
  if (ventes.isEmpty) return [];

  final triees = List<Vente>.from(ventes)..sort((a, b) => b.date.compareTo(a.date));
  final maintenant = DateTime.now();
  final aujourdHui = DateTime(maintenant.year, maintenant.month, maintenant.day);
  final hier = aujourdHui.subtract(const Duration(days: 1));

  final groupes = <_GroupeVente>[];
  String? currentKey;
  int? currentTotal;
  List<Vente>? currentVentes;

  for (final vente in triees) {
    final dateVente = DateTime.tryParse(vente.date) ?? maintenant;
    final dateOnly = DateTime(dateVente.year, dateVente.month, dateVente.day);
    String titre;
    if (dateOnly == aujourdHui) {
      titre = 'Aujourd\'hui';
    } else if (dateOnly == hier) {
      titre = 'Hier';
    } else {
      titre = DateFormat.yMMMMd('fr_FR').format(dateOnly);
    }

    if (titre != currentKey) {
      if (currentKey != null) {
        groupes.add(_GroupeVente(titre: currentKey, total: currentTotal!, ventes: currentVentes!));
      }
      currentKey = titre;
      currentTotal = 0;
      currentVentes = [];
    }
    currentTotal = currentTotal! + vente.totalNet;
    currentVentes!.add(vente);
  }
  if (currentKey != null) {
    groupes.add(_GroupeVente(titre: currentKey, total: currentTotal!, ventes: currentVentes!));
  }
  return groupes;
});

class VentesPage extends ConsumerStatefulWidget {
  const VentesPage({super.key});

  @override
  ConsumerState<VentesPage> createState() => _VentesPageState();
}

class _VentesPageState extends ConsumerState<VentesPage> {
  final _searchController = TextEditingController();
  String _query = '';
  int _filtrePeriode = 0; // 0 = Toutes, 1 = Aujourd'hui, 2 = Ce mois

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

  @override
  Widget build(BuildContext context) {
    final toutesVentes = ref.watch(toutesVentesProvider).valueOrNull ?? [];
    final groupes = ref.watch(ventesGroupeesProvider);
    final clientMap = ref.watch(clientMapProvider);
    final masque = ref.watch(masquerMontantsProvider);

    // Calculs globaux pour la carte d'en-tête
    final int totalCA = toutesVentes.fold<int>(0, (sum, v) => sum + v.totalNet);
    final int panierMoyen = toutesVentes.isEmpty ? 0 : (totalCA / toutesVentes.length).round();

    // Filtrage par période & recherche
    final maintenant = DateTime.now();
    List<_GroupeVente> groupesFiltres = groupes;

    if (_filtrePeriode == 1) {
      // Aujourd'hui
      groupesFiltres = groupesFiltres.where((g) => g.titre == 'Aujourd\'hui').toList();
    } else if (_filtrePeriode == 2) {
      // Ce mois
      groupesFiltres = groupesFiltres.map((g) {
        final ventesMois = g.ventes.where((v) {
          final d = DateTime.tryParse(v.date);
          return d != null && d.year == maintenant.year && d.month == maintenant.month;
        }).toList();
        if (ventesMois.isEmpty) return null;
        final total = ventesMois.fold<int>(0, (sum, v) => sum + v.totalNet);
        return _GroupeVente(titre: g.titre, total: total, ventes: ventesMois);
      }).whereType<_GroupeVente>().toList();
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      groupesFiltres = groupesFiltres.map((g) {
        final ventesFiltrees = g.ventes.where((v) {
          final numeroMatch = v.numero.toLowerCase().contains(q);
          final client = clientMap[v.clientId];
          final clientMatch = client?.nom.toLowerCase().contains(q) ?? false;
          final vendeurMatch = v.vendeur.toLowerCase().contains(q);
          return numeroMatch || clientMatch || vendeurMatch;
        }).toList();
        if (ventesFiltrees.isEmpty) return null;
        final totalFiltre = ventesFiltrees.fold<int>(0, (sum, v) => sum + v.totalNet);
        return _GroupeVente(titre: g.titre, total: totalFiltre, ventes: ventesFiltrees);
      }).whereType<_GroupeVente>().toList();
    }

    final totalVentesVisibles = groupesFiltres.fold<int>(0, (sum, g) => sum + g.ventes.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête statistiques Ventes (Hero Card)
        Padding(
          padding: const EdgeInsets.fromLTRB(Espace.page, Espace.sm, Espace.page, Espace.xs),
          child: Container(
            padding: const EdgeInsets.all(Espace.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Rayon.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Color.lerp(Theme.of(context).colorScheme.primary, const Color(0xFF3A86EF), 0.45)!,
                  const Color(0xFF1E3A8A),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 18,
                  spreadRadius: -3,
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
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: Espace.md),
                        const Text(
                          'Journal des ventes',
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '$totalVentesVisibles vente(s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Row(
                  children: [
                    Expanded(
                      child: _HeaderStatItem(
                        label: 'Chiffre d\'affaires',
                        valeur: masque ? '•••• GNF' : fmtGNF(totalCA),
                        icone: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                    Container(height: 36, width: 1, color: Colors.white.withValues(alpha: 0.25)),
                    Expanded(
                      child: _HeaderStatItem(
                        label: 'Panier moyen',
                        valeur: masque ? '•••• GNF' : fmtGNF(panierMoyen),
                        icone: Icons.shopping_bag_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Barre de recherche
        AppSearchBar(
          controller: _searchController,
          hintText: 'Rechercher un numéro, un client, un vendeur…',
          onChanged: (v) => setState(() => _query = v),
        ),

        // Chips de filtre rapide
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Espace.page),
          child: Row(
            children: [
              _FiltreChip(
                label: 'Toutes',
                actif: _filtrePeriode == 0,
                onTap: () => setState(() => _filtrePeriode = 0),
              ),
              const SizedBox(width: Espace.xs),
              _FiltreChip(
                label: 'Aujourd\'hui',
                actif: _filtrePeriode == 1,
                onTap: () => setState(() => _filtrePeriode = 1),
              ),
              const SizedBox(width: Espace.xs),
              _FiltreChip(
                label: 'Ce mois',
                actif: _filtrePeriode == 2,
                onTap: () => setState(() => _filtrePeriode = 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: Espace.xs),

        // Liste des ventes
        Expanded(
          child: groupesFiltres.isEmpty
              ? EtatVide(
                  icone: _query.isEmpty
                      ? Icons.point_of_sale_outlined
                      : Icons.search_off_rounded,
                  message: _query.isEmpty
                      ? 'Aucune vente enregistrée'
                      : 'Aucun résultat',
                  description: _query.isEmpty
                      ? 'Appuyez sur le bouton + pour créer votre première vente.'
                      : 'Essayez un autre terme de recherche.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: Espace.basDeListe),
                  itemCount: groupesFiltres.length,
                  itemBuilder: (context, index) {
                    final groupe = groupesFiltres[index];
                    return _buildGroupe(context, groupe, clientMap, masque);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGroupe(BuildContext context, _GroupeVente groupe, Map<String, Client> clientMap, bool masque) {
    final theme = Theme.of(context);
    final totalAffiche = masque ? '•••• GNF' : fmtGNF(groupe.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Espace.page, Espace.md, Espace.page, Espace.xs),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Espace.xs + 2),
              Expanded(
                child: Text(
                  groupe.titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: Espace.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Rayon.pilule),
                ),
                child: Text(
                  totalAffiche,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        ...groupe.ventes.map((vente) => _VenteCard(
              vente: vente,
              client: clientMap[vente.clientId],
              masque: masque,
              onTap: () => showModalBottomSheet(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                showDragHandle: false,
                backgroundColor: Colors.transparent,
                elevation: 0,
                builder: (_) => VenteDetailSheet(vente: vente),
              ),
            )),
      ],
    );
  }
}

class _HeaderStatItem extends StatelessWidget {
  final String label;
  final String valeur;
  final IconData icone;

  const _HeaderStatItem({
    required this.label,
    required this.valeur,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: Colors.white.withValues(alpha: 0.8), size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valeur,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltreChip extends StatelessWidget {
  final String label;
  final bool actif;
  final VoidCallback onTap;

  const _FiltreChip({
    required this.label,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Rayon.pilule),
      child: AnimatedContainer(
        duration: Duree.rapide,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: actif
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(Rayon.pilule),
          border: Border.all(
            color: actif
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: actif ? Colors.white : theme.colorScheme.onSurfaceVariant,
            fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _VenteCard extends StatelessWidget {
  final Vente vente;
  final Client? client;
  final bool masque;
  final VoidCallback onTap;

  const _VenteCard({
    required this.vente,
    required this.client,
    required this.masque,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enAttente = vente.numero.isEmpty;
    final numero = enAttente ? 'En attente…' : vente.numero;
    final clientNom = client?.nom ?? 'Client de passage';
    final prixAffiche = masque ? '•••• GNF' : fmtGNF(vente.totalNet);
    final heure = fmtHeureIso(vente.date);

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(horizontal: Espace.page, vertical: 4),
      padding: const EdgeInsets.all(Espace.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: enAttente
                    ? [Colors.orange.withValues(alpha: 0.2), Colors.orange.withValues(alpha: 0.08)]
                    : [theme.colorScheme.primary.withValues(alpha: 0.18), theme.colorScheme.primary.withValues(alpha: 0.05)],
              ),
              borderRadius: BorderRadius.circular(Rayon.md),
              border: Border.all(
                color: enAttente
                    ? Colors.orange.withValues(alpha: 0.3)
                    : theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              enAttente
                  ? Icons.hourglass_empty_rounded
                  : Icons.receipt_long_rounded,
              size: 20,
              color: enAttente ? Colors.orange : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: Espace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        numero,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (enAttente) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(Rayon.pilule),
                        ),
                        child: const Text(
                          'En attente',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 13, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        clientNom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${vente.lignes.length} article(s) • $heure'
                  '${vente.vendeur.isNotEmpty ? ' • ${vente.vendeur}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Espace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    prixAffiche,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}