import '../../core/models/models.dart';

// ─── Rapport d'activité : les données ─────────────────────────────────────────
// Transposition de `src/lib/rapport.ts` et de `calculerBilan` (`src/lib/finance.ts`)
// de l'application web. Les deux applications partagent le même serveur : un
// rapport imprimé depuis le téléphone doit annoncer exactement les mêmes
// chiffres que celui imprimé depuis le navigateur, sans quoi le gérant a deux
// documents contradictoires à montrer à sa banque.
//
// Le rapport ne calcule RIEN qu'il pourrait emprunter : les totaux d'argent
// viennent tous du bilan. Aucune projection, aucune extrapolation : une journée
// sans vente vaut zéro, elle n'est pas lissée.

// `Periode`, `dansPeriode`, `natureDe`, `Bilan` et `calculerBilan` viennent du
// moteur financier (`core/finance/finance_engine.dart`, réexporté par
// `models.dart`). Ce fichier en avait autrefois sa propre copie : deux
// implémentations du même bilan vivaient dans l'application, l'une servant
// l'écran Finances et l'autre le PDF. Tant qu'elles étaient d'accord, personne
// ne le voyait ; le jour où l'une aurait bougé, le rapport imprimé aurait
// contredit l'écran — et c'est le rapport que le gérant montre à sa banque.

String _p2(int n) => n.toString().padLeft(2, '0');

const _mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const _jours = [
  'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
];

String _dateFR(String isoJour) {
  final m = isoJour.split('-');
  if (m.length != 3) return isoJour;
  final mois = int.tryParse(m[1]) ?? 1;
  return '${int.tryParse(m[2]) ?? 0} ${_mois[(mois - 1).clamp(0, 11)]} ${m[0]}';
}

int _nbJours(Periode p) {
  final d = DateTime.tryParse(p.debut), f = DateTime.tryParse(p.fin);
  if (d == null || f == null) return 1;
  return f.difference(d).inDays + 1;
}

/// Une période nommée : ce que l'utilisateur a demandé, et ses bornes.
///
/// Le libellé est écrit une seule fois, ici : il part sur la couverture du PDF,
/// dans le nom du fichier et dans l'en-tête de chaque section, et ces trois-là
/// ne doivent jamais se contredire.
class PeriodeChoisie {
  final Periode periode;
  final String libelle;
  const PeriodeChoisie({required this.periode, required this.libelle});
}

/// Compose la période et son libellé à partir de deux dates.
///
/// Le libellé suit celui de l'application web : « Juillet 2026 » quand les
/// bornes couvrent exactement un mois civil, « Année 2026 » pour une année,
/// « Lundi 13 juillet 2026 » pour un jour, sinon « Du … au … ».
PeriodeChoisie composerPeriode(DateTime debut, DateTime fin) {
  final p = Periode(debut: isoJour(debut), fin: isoJour(fin));

  if (p.debut == p.fin) {
    final nomJour = _jours[(debut.weekday - 1).clamp(0, 6)];
    return PeriodeChoisie(
      periode: p,
      libelle:
          '${nomJour[0].toUpperCase()}${nomJour.substring(1)} ${_dateFR(p.debut)}',
    );
  }

  final premierDuMois = DateTime(debut.year, debut.month, 1);
  final dernierDuMois = DateTime(debut.year, debut.month + 1, 0);
  if (isoJour(premierDuMois) == p.debut && isoJour(dernierDuMois) == p.fin) {
    final nom = _mois[debut.month - 1];
    return PeriodeChoisie(
      periode: p,
      libelle: '${nom[0].toUpperCase()}${nom.substring(1)} ${debut.year}',
    );
  }

  if (p.debut == '${debut.year}-01-01' && p.fin == '${debut.year}-12-31') {
    return PeriodeChoisie(periode: p, libelle: 'Année ${debut.year}');
  }

  return PeriodeChoisie(
    periode: p,
    libelle: 'Du ${_dateFR(p.debut)} au ${_dateFR(p.fin)}',
  );
}

/// Nom de fichier proposé au partage : rapport-2026-07-13_2026-07-19.
String nomFichierRapport(PeriodeChoisie p) => p.periode.debut == p.periode.fin
    ? 'rapport-${p.periode.debut}'
    : 'rapport-${p.periode.debut}_${p.periode.fin}';

// ─── Structure du rapport ─────────────────────────────────────────────────────

class LigneArticleVendu {
  final String ref, nom, categorie, unite;
  int qte, chiffreAffaires;

  /// `null` quand le compte ne voit pas les prix d'achat.
  int? marge;

  LigneArticleVendu({
    required this.ref,
    required this.nom,
    required this.categorie,
    required this.unite,
    this.qte = 0,
    this.chiffreAffaires = 0,
    this.marge,
  });
}

class LigneClientRapport {
  final String nom, type;
  int nbVentes, chiffreAffaires, resteDu;
  LigneClientRapport({
    required this.nom,
    required this.type,
    this.nbVentes = 0,
    this.chiffreAffaires = 0,
    this.resteDu = 0,
  });
}

class LigneVenteRapport {
  final String numero, date, client, vendeur;
  final int nbLignes, total, resteDu;
  const LigneVenteRapport({
    required this.numero,
    required this.date,
    required this.client,
    required this.vendeur,
    required this.nbLignes,
    required this.total,
    required this.resteDu,
  });
}

class LigneImpaye {
  final String numero, client, dateEmission, dateEcheance;
  final int montant, paye, reste, joursRetard;
  const LigneImpaye({
    required this.numero,
    required this.client,
    required this.dateEmission,
    required this.dateEcheance,
    required this.montant,
    required this.paye,
    required this.reste,
    required this.joursRetard,
  });
}

class LigneDepenseRapport {
  final String numero, date, libelle, categorie, beneficiaire;
  final int montant, regle, reste;
  const LigneDepenseRapport({
    required this.numero,
    required this.date,
    required this.libelle,
    required this.categorie,
    required this.beneficiaire,
    required this.montant,
    required this.regle,
    required this.reste,
  });
}

class PointSerie {
  /// Étiquette courte affichée sous la barre : « 14 », « lun. », « juil. ».
  final String label;
  int chiffreAffaires, encaissements, decaissements;
  PointSerie(this.label,
      {this.chiffreAffaires = 0, this.encaissements = 0, this.decaissements = 0});
}

class LigneEncaissementMode {
  final String mode;
  int montant, nombre;
  LigneEncaissementMode(this.mode, {this.montant = 0, this.nombre = 0});
}

class SectionStock {
  /// Valeur du stock au prix d'achat. `null` si le compte ne voit pas les prix
  /// d'achat.
  final int? valeurAchat;
  final int valeurVente;
  final int nbReferences;
  final List<Article> ruptures;
  final List<Article> faibles;
  final int entrees, sorties, nbMouvements;
  const SectionStock({
    required this.valeurAchat,
    required this.valeurVente,
    required this.nbReferences,
    required this.ruptures,
    required this.faibles,
    required this.entrees,
    required this.sorties,
    required this.nbMouvements,
  });
}

class RapportComplet {
  final PeriodeChoisie choix;
  final DateTime genereLe;
  final String generePar;
  final bool voitPrixAchat;

  final Bilan bilan;
  final List<PointSerie> serie;

  /// Ce que la série découpe : un point par jour ou un point par mois.
  final String pasSerie;

  final List<LigneVenteRapport> ventes;
  final List<LigneArticleVendu> articlesVendus;
  final List<LigneClientRapport> clients;
  final int nbClientsServis;

  /// Vente moyenne = chiffre d'affaires ÷ nombre de ventes. `null` sans vente.
  final int? panierMoyen;

  final List<LigneEncaissementMode> encaissementsParMode;
  final int facturesEmises, montantFacture;
  final List<LigneImpaye> impayes;

  final List<LigneDepenseRapport> depenses;
  final SectionStock stock;

  const RapportComplet({
    required this.choix,
    required this.genereLe,
    required this.generePar,
    required this.voitPrixAchat,
    required this.bilan,
    required this.serie,
    required this.pasSerie,
    required this.ventes,
    required this.articlesVendus,
    required this.clients,
    required this.nbClientsServis,
    required this.panierMoyen,
    required this.encaissementsParMode,
    required this.facturesEmises,
    required this.montantFacture,
    required this.impayes,
    required this.depenses,
    required this.stock,
  });
}

/// Construit le rapport complet d'une période.
///
/// [voitPrixAchat] n'est pas qu'un réglage d'affichage : quand il est faux, la
/// marge et la valeur d'achat du stock ne sont pas calculées du tout. Les
/// masquer à l'écran mais les écrire dans le PDF reviendrait à les publier.
RapportComplet construireRapport({
  required PeriodeChoisie choix,
  required List<Article> articles,
  required List<Vente> ventes,
  required List<Client> clients,
  required List<Facture> factures,
  required List<Depense> depenses,
  required List<MouvementStock> mouvements,
  required String generePar,
  required bool voitPrixAchat,
}) {
  final p = choix.periode;
  final parIdArticle = {for (final a in articles) a.id: a};
  final parIdClient = {for (final c in clients) c.id: c};

  final bilan = calculerBilan(
      ventes: ventes,
      factures: factures,
      depenses: depenses,
      articles: articles,
      periode: p);

  final ventesPeriode = ventes.where((v) => dansPeriode(v.date, p)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  String nomClient(String id) => parIdClient[id]?.nom ?? 'Client de passage';
  final factureParVente = {for (final f in factures) f.venteId: f};

  // ── Ventes de la période ──
  final lignesVentes = ventesPeriode.map((v) {
    final f = factureParVente[v.id];
    return LigneVenteRapport(
      numero: v.numero.isEmpty ? '—' : v.numero,
      date: v.date,
      client: nomClient(v.clientId),
      vendeur: v.vendeur,
      nbLignes: v.lignes.length,
      total: v.totalNet,
      resteDu: f == null ? 0 : resteDu(f),
    );
  }).toList();

  // ── Articles vendus, du plus gros contributeur au plus petit ──
  final parArticle = <String, LigneArticleVendu>{};
  for (final v in ventesPeriode) {
    for (final l in v.lignes) {
      final a = parIdArticle[l.articleId];
      final e = parArticle.putIfAbsent(
          l.articleId,
          () => LigneArticleVendu(
                ref: l.articleRef.isNotEmpty ? l.articleRef : (a?.ref ?? ''),
                nom: l.articleNom.isNotEmpty
                    ? l.articleNom
                    : (a?.nom ?? 'Article supprimé'),
                categorie: a?.categorie ?? '—',
                unite: l.unite.isNotEmpty ? l.unite : (a?.unite ?? ''),
                marge: voitPrixAchat ? 0 : null,
              ));
      e.qte += l.qte;
      e.chiffreAffaires += l.total;
      if (e.marge != null) {
        e.marge = e.marge! + l.total - (a?.prixAchat ?? 0) * l.qte;
      }
    }
  }
  final articlesVendus = parArticle.values.toList()
    ..sort((a, b) => b.chiffreAffaires.compareTo(a.chiffreAffaires));

  // ── Clients servis sur la période ──
  final parClient = <String, LigneClientRapport>{};
  for (final v in ventesPeriode) {
    final c = parIdClient[v.clientId];
    final e = parClient.putIfAbsent(
        v.clientId,
        () => LigneClientRapport(
            nom: c?.nom ?? 'Client de passage', type: c?.type ?? '—'));
    e.nbVentes++;
    e.chiffreAffaires += v.totalNet;
  }
  // Le reste dû est celui du client dans son ensemble, pas seulement sur les
  // ventes de la période : c'est le chiffre qu'on veut avoir sous les yeux au
  // moment de relancer, et il inclut donc les vieilles factures.
  for (final entree in parClient.entries) {
    entree.value.resteDu = factures
        .where((f) => f.clientId == entree.key)
        .fold<int>(0, (s, f) => s + resteDu(f));
  }
  final lignesClients = parClient.values.toList()
    ..sort((a, b) => b.chiffreAffaires.compareTo(a.chiffreAffaires));

  // ── Encaissements de la période, ventilés par mode de règlement ──
  final parMode = <String, LigneEncaissementMode>{};
  for (final f in factures) {
    for (final pay in f.paiements) {
      if (!dansPeriode(pay.date, p)) continue;
      final mode = pay.mode.isEmpty ? 'espèces' : pay.mode;
      final e = parMode.putIfAbsent(mode, () => LigneEncaissementMode(mode));
      e.montant += pay.montant;
      e.nombre++;
    }
  }
  final encaissementsParMode = parMode.values.toList()
    ..sort((a, b) => b.montant.compareTo(a.montant));

  // ── Facturation ──
  final facturesPeriode =
      factures.where((f) => dansPeriode(f.dateEmission, p)).toList();

  // Les impayés sont un ARRÊTÉ, pas un flux : toutes les factures encore dues,
  // y compris celles émises avant la période. Ne montrer que les impayés de la
  // semaine écoulée donnerait l'illusion que les vieilles créances ont disparu.
  final finPeriode = DateTime.tryParse('${p.fin}T23:59:59') ?? DateTime.now();
  final impayes = factures
      .where((f) =>
          f.dateEmission.length >= 10 &&
          f.dateEmission.substring(0, 10).compareTo(p.fin) <= 0 &&
          resteDu(f) > 0)
      .map((f) {
        final echeance = DateTime.tryParse(f.dateEcheance);
        return LigneImpaye(
          numero: f.numero.isEmpty ? '—' : f.numero,
          client: nomClient(f.clientId),
          dateEmission: f.dateEmission,
          dateEcheance: f.dateEcheance,
          montant: f.montantTTC,
          paye: montantPaye(f),
          reste: resteDu(f),
          joursRetard: echeance == null
              ? 0
              : finPeriode.difference(echeance).inDays.clamp(0, 1 << 30),
        );
      })
      .toList()
    ..sort((a, b) => b.joursRetard != a.joursRetard
        ? b.joursRetard - a.joursRetard
        : b.reste - a.reste);

  // ── Dépenses engagées sur la période ──
  final lignesDepenses = (depenses.where((d) => dansPeriode(d.date, p)).toList()
        ..sort((a, b) => a.date.compareTo(b.date)))
      .map((d) => LigneDepenseRapport(
            numero: d.numero.isEmpty ? '—' : d.numero,
            date: d.date,
            libelle: d.libelle,
            categorie: d.categorie,
            beneficiaire: d.beneficiaire,
            montant: d.montant,
            regle: montantRegle(d),
            reste: resteAPayer(d),
          ))
      .toList();

  // ── Stock : un état au moment de l'édition, pas une photo du passé ──
  // Le stock n'est pas historisé : on ne peut pas dire ce qu'il valait un mardi
  // de mars. Les valeurs ci-dessous sont donc celles d'AUJOURD'HUI, et le PDF le
  // dit noir sur blanc — un chiffre daté à tort serait pire qu'absent.
  final mvtsPeriode = mouvements.where((m) => dansPeriode(m.date, p)).toList();
  final stock = SectionStock(
    valeurAchat: voitPrixAchat
        ? articles.fold<int>(0, (s, a) => s + a.prixAchat * a.stock)
        : null,
    valeurVente: articles.fold<int>(0, (s, a) => s + a.prixVente * a.stock),
    nbReferences: articles.length,
    ruptures: articles.where((a) => stockStatut(a) == 'rupture').toList(),
    faibles: articles.where((a) => stockStatut(a) == 'faible').toList(),
    entrees: mvtsPeriode
        .where((m) => m.type == 'entrée')
        .fold<int>(0, (s, m) => s + m.quantite),
    sorties: mvtsPeriode
        .where((m) => m.type == 'sortie')
        .fold<int>(0, (s, m) => s + m.quantite),
    nbMouvements: mvtsPeriode.length,
  );

  final serie = _construireSerie(
      ventes: ventes, factures: factures, depenses: depenses, periode: p);

  return RapportComplet(
    choix: choix,
    genereLe: DateTime.now(),
    generePar: generePar,
    voitPrixAchat: voitPrixAchat,
    bilan: bilan,
    serie: serie.$1,
    pasSerie: serie.$2,
    ventes: lignesVentes,
    articlesVendus: articlesVendus,
    clients: lignesClients,
    nbClientsServis: parClient.length,
    panierMoyen: ventesPeriode.isEmpty
        ? null
        : (bilan.chiffreAffaires / ventesPeriode.length).round(),
    encaissementsParMode: encaissementsParMode,
    facturesEmises: facturesPeriode.length,
    montantFacture: facturesPeriode.fold<int>(0, (s, f) => s + f.montantTTC),
    impayes: impayes,
    depenses: lignesDepenses,
    stock: stock,
  );
}

/// Découpe la période en points de graphique. Au-delà de deux mois, on passe au
/// pas mensuel : soixante barres larges de deux millimètres sur une page A4 ne
/// se lisent pas, et un rapport annuel se lit mois par mois de toute façon.
(List<PointSerie>, String) _construireSerie({
  required List<Vente> ventes,
  required List<Facture> factures,
  required List<Depense> depenses,
  required Periode periode,
}) {
  final jours = _nbJours(periode);
  final pas = jours <= 62 ? 'jour' : 'mois';

  final seaux = <String, PointSerie>{};
  final ordre = <String>[];
  void ajouter(String cle, String label) {
    if (seaux.containsKey(cle)) return;
    seaux[cle] = PointSerie(label);
    ordre.add(cle);
  }

  final debut = DateTime.tryParse(periode.debut);
  final fin = DateTime.tryParse(periode.fin);
  if (debut == null || fin == null) return (<PointSerie>[], pas);

  if (pas == 'jour') {
    var d = debut;
    while (!d.isAfter(fin)) {
      // Sur une semaine, le nom du jour parle plus que son quantième ; au-delà,
      // sept « lun. » identiques ne distinguent plus rien.
      final label = jours <= 8
          ? '${_jours[(d.weekday - 1).clamp(0, 6)].substring(0, 3)}.'
          : '${d.day}';
      ajouter(isoJour(d), label);
      d = DateTime(d.year, d.month, d.day + 1);
    }
  } else {
    var d = DateTime(debut.year, debut.month, 1);
    while (!d.isAfter(fin)) {
      ajouter('${d.year}-${_p2(d.month)}',
          _mois[d.month - 1].substring(0, _mois[d.month - 1].length.clamp(0, 4)));
      d = DateTime(d.year, d.month + 1, 1);
    }
  }

  void verser(String? date, String champ, int montant) {
    if (!dansPeriode(date, periode)) return;
    final cle = pas == 'jour' ? date!.substring(0, 10) : date!.substring(0, 7);
    final e = seaux[cle];
    if (e == null) return;
    switch (champ) {
      case 'ca':
        e.chiffreAffaires += montant;
      case 'enc':
        e.encaissements += montant;
      default:
        e.decaissements += montant;
    }
  }

  for (final v in ventes) {
    verser(v.date, 'ca', v.totalNet);
  }
  for (final f in factures) {
    for (final p in f.paiements) {
      verser(p.date, 'enc', p.montant);
    }
  }
  for (final d in depenses) {
    for (final r in d.reglements) {
      verser(r.date, 'dec', r.montant);
    }
  }

  return (ordre.map((c) => seaux[c]!).toList(), pas);
}
