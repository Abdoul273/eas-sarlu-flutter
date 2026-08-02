// lib/core/finance/finance_engine.dart
import 'dart:math';

import '../models/models.dart';

// ─── Calculs financiers ───────────────────────────────────────────────────────
// Transposition de `src/lib/finance.ts` et `src/lib/depenses.ts` de l'application
// web. Les deux applications partagent le même serveur : un chiffre lu sur le
// téléphone doit être le même que celui lu au navigateur, sinon le gérant a deux
// vérités contradictoires sous les yeux.
//
// Un seul endroit fait les additions d'argent. Toute page qui affiche un solde,
// une créance ou un total passe par ici : c'est la seule façon d'être certain
// que le tableau de bord, la fiche client, la liste des factures et le rapport
// imprimé annoncent le même chiffre.
//
// Les montants sont en francs guinéens, sans décimales. Le magasin ne facture ni
// ne récupère la TVA, et n'accorde pas de remise : un seul montant, celui qui
// entre ou sort réellement de la caisse. Les champs `tauxTVA` et `remise`
// existent malgré tout dans les enregistrements, parce que le serveur et
// l'application web les portent — ils sont lus fidèlement, jamais inventés.

// ─── Catalogue des dépenses & natures comptables ──────────────────────────────
// La nature comptable n'est pas laissée au choix de celui qui saisit : elle est
// attachée à la catégorie, une fois pour toutes. C'est ce qui garantit qu'un
// achat de tôle ne sera jamais compté comme une charge du mois par erreur, quel
// que soit l'utilisateur ou le jour.

class CategorieDepenseDef {
  final String cle;
  final String nature; // "marchandise" | "exploitation" | "investissement"

  /// Ce que la catégorie recouvre, affiché à la saisie.
  final String aide;

  const CategorieDepenseDef({
    required this.cle,
    required this.nature,
    required this.aide,
  });
}

const List<CategorieDepenseDef> categoriesDepenseDef = [
  CategorieDepenseDef(
    cle: 'Achat de marchandise',
    nature: 'marchandise',
    aide:
        "Fer, tôle, profilés destinés à la revente. Entre dans le résultat à la vente, pas à l'achat.",
  ),
  CategorieDepenseDef(
    cle: 'Transport & manutention',
    nature: 'exploitation',
    aide: 'Camion, déchargement, portage de la marchandise.',
  ),
  CategorieDepenseDef(
    cle: "Salaires & main-d'œuvre",
    nature: 'exploitation',
    aide: 'Paies, journaliers, primes.',
  ),
  CategorieDepenseDef(
    cle: 'Loyer',
    nature: 'exploitation',
    aide: 'Location du dépôt, du magasin, du terrain.',
  ),
  CategorieDepenseDef(
    cle: 'Électricité & eau',
    nature: 'exploitation',
    aide: 'EDG, SEG, groupe électrogène (hors carburant).',
  ),
  CategorieDepenseDef(
    cle: 'Carburant',
    nature: 'exploitation',
    aide: 'Gasoil, essence : véhicules et groupe.',
  ),
  CategorieDepenseDef(
    cle: 'Entretien & réparations',
    nature: 'exploitation',
    aide: 'Réparation du camion, du matériel, du bâtiment.',
  ),
  CategorieDepenseDef(
    cle: 'Taxes & impôts',
    nature: 'exploitation',
    aide: 'Patente, impôts, taxes communales, douane.',
  ),
  CategorieDepenseDef(
    cle: 'Frais bancaires',
    nature: 'exploitation',
    aide: 'Agios, commissions, frais de transfert et mobile money.',
  ),
  CategorieDepenseDef(
    cle: 'Téléphone & internet',
    nature: 'exploitation',
    aide: 'Crédit, forfaits, connexion du magasin.',
  ),
  CategorieDepenseDef(
    cle: 'Sécurité & gardiennage',
    nature: 'exploitation',
    aide: 'Gardiens, surveillance du dépôt.',
  ),
  CategorieDepenseDef(
    cle: 'Fournitures & bureau',
    nature: 'exploitation',
    aide: 'Papeterie, carnets de reçus, encre, petit matériel de bureau.',
  ),
  CategorieDepenseDef(
    cle: 'Publicité & représentation',
    nature: 'exploitation',
    aide: 'Enseigne, cartes de visite, démarchage.',
  ),
  CategorieDepenseDef(
    cle: 'Équipement & outillage',
    nature: 'investissement',
    aide: 'Soudeuse, disqueuse, balance, matériel qui durera des années.',
  ),
  CategorieDepenseDef(
    cle: 'Véhicule',
    nature: 'investissement',
    aide: "Achat d'un camion, d'une moto, d'un tricycle.",
  ),
  CategorieDepenseDef(
    cle: 'Travaux & aménagement',
    nature: 'investissement',
    aide: 'Construction ou aménagement du dépôt, hangar, clôture.',
  ),
  CategorieDepenseDef(
    cle: 'Divers',
    nature: 'exploitation',
    aide: "Ce qui n'entre dans aucune autre catégorie.",
  ),
];

final Map<String, CategorieDepenseDef> _categoriesMap = {
  for (final c in categoriesDepenseDef) c.cle: c
};

/// Nature d'une catégorie. Une catégorie inconnue (venue d'une sauvegarde plus
/// ancienne ou d'une saisie libre) est traitée comme une charge d'exploitation :
/// c'est le choix prudent, il pèse sur le résultat plutôt que de l'embellir.
String natureDe(String categorie) =>
    _categoriesMap[categorie]?.nature ?? 'exploitation';

String aideDe(String categorie) => _categoriesMap[categorie]?.aide ?? '';

const Map<String, String> libelleNature = {
  'marchandise': 'Achat de marchandise',
  'exploitation': "Charge d'exploitation",
  'investissement': 'Investissement',
};

/// Couleur d'accent par nature, identique à celle de l'application web.
const Map<String, int> couleurNature = {
  'marchandise': 0xff1D4ED8,
  'exploitation': 0xffE85D04,
  'investissement': 0xff7C3AED,
};

/// Explication affichée à côté de chaque nature. Sans elle, un utilisateur qui
/// voit « cette dépense ne réduit pas le résultat » croit à un bug.
String explicationNature(String nature) {
  switch (nature) {
    case 'marchandise':
      return "Sort de la caisse aujourd'hui, mais ne pèse sur le résultat qu'au moment où la marchandise est vendue.";
    case 'investissement':
      return "Bien durable : sort de la caisse mais ne s'impute pas d'un coup sur le résultat.";
    case 'exploitation':
    default:
      return 'Charge du mois : se déduit intégralement de la marge sur la période où elle est engagée.';
  }
}

// ─── Remises ──────────────────────────────────────────────────────────────────
// Le magasin n'accorde pas de remise, et l'application Android n'en fait pas
// saisir. Ces deux fonctions servent à LIRE : une vente enregistrée depuis
// l'application web peut en porter une, et elle doit s'afficher juste.

/// Valide une saisie de remise (pourcentage entre 0 et 100).
bool remiseValide(String saisie) {
  if (saisie.trim().isEmpty) return true;
  final v = double.tryParse(saisie);
  return v != null && v.isFinite && v >= 0 && v <= 100;
}

/// Borne une remise entre 0 et 100 %. Une remise hors de ces bornes n'est pas
/// une remise : elle rendrait le total négatif ou supérieur au prix affiché.
double borneRemise(num? remise) {
  if (remise == null || !remise.isFinite) return 0.0;
  return max(0.0, min(remise.toDouble(), 100.0));
}

// ─── Période & filtrage sur dates ISO ─────────────────────────────────────────

/// Une période fermée [debut, fin], bornes incluses, en dates ISO « aaaa-mm-jj ».
/// Les comparaisons se font sur la chaîne : au format ISO, l'ordre
/// lexicographique est l'ordre chronologique.
class Periode {
  final String debut; // "aaaa-mm-jj"
  final String fin; // "aaaa-mm-jj"

  const Periode({required this.debut, required this.fin});

  /// Bornes d'un mois civil. [mois] va de 1 à 12.
  factory Periode.mois(int annee, int mois) {
    final dernierJour = DateTime(annee, mois + 1, 0).day;
    return Periode(
      debut: '$annee-${_p2(mois)}-01',
      fin: '$annee-${_p2(mois)}-${_p2(dernierJour)}',
    );
  }

  /// Bornes d'une année civile.
  factory Periode.annee(int annee) =>
      Periode(debut: '$annee-01-01', fin: '$annee-12-31');

  /// Les [n] derniers jours, aujourd'hui inclus.
  factory Periode.derniersJours(int n, [DateTime? maintenant]) {
    final fin = maintenant ?? DateTime.now();
    final debut = fin.subtract(Duration(days: n - 1));
    return Periode(debut: isoJour(debut), fin: isoJour(fin));
  }

  /// Bornes d'une seule journée.
  factory Periode.jour(DateTime d) {
    final s = isoJour(d);
    return Periode(debut: s, fin: s);
  }

  @override
  bool operator ==(Object other) =>
      other is Periode && other.debut == debut && other.fin == fin;

  @override
  int get hashCode => Object.hash(debut, fin);

  @override
  String toString() => 'Periode($debut → $fin)';
}

/// Un intervalle de dates choisi à l'écran par un sélecteur.
///
/// Distinct de [Periode], qui porte des dates ISO et sert aux calculs : ici on
/// manipule des `DateTime`, parce que c'est ce que rendent les sélecteurs de
/// date de Flutter. `periode` fait la conversion une bonne fois — les écrans
/// Finances et Rapports la refaisaient chacun à la main, trois fois, avec leur
/// propre fonction de rembourrage.
class PlageDates {
  final DateTime debut;
  final DateTime fin;

  const PlageDates({required this.debut, required this.fin});

  /// Le mois civil contenant [reference], du 1er au dernier jour.
  factory PlageDates.mois(DateTime reference) => PlageDates(
        debut: DateTime(reference.year, reference.month, 1),
        fin: DateTime(reference.year, reference.month + 1, 0),
      );

  /// Les bornes en dates ISO, telles que les attendent les calculs.
  Periode get periode => Periode(debut: isoJour(debut), fin: isoJour(fin));

  /// Vrai si [date] tombe dans l'intervalle, bornes incluses.
  bool contient(DateTime date) => !date.isBefore(debut) && !date.isAfter(fin);

  @override
  bool operator ==(Object other) =>
      other is PlageDates && other.debut == debut && other.fin == fin;

  @override
  int get hashCode => Object.hash(debut, fin);
}

String _p2(int n) => n.toString().padLeft(2, '0');

/// Date d'un `DateTime` au format « aaaa-mm-jj », en heure locale.
///
/// `toIso8601String()` ne convient pas : il passe par UTC pour les dates
/// construites en UTC, et une vente encaissée à 23 h à Conakry basculerait au
/// lendemain — elle tomberait dans le mauvais mois sur un arrêté de fin de mois.
String isoJour(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';

/// La date [iso] tombe-t-elle dans la période, bornes incluses ?
/// Une période absente accepte tout : c'est le « depuis toujours » du web.
bool dansPeriode(String? iso, Periode? p) {
  if (p == null) return true;
  if (iso == null || iso.length < 10) return false;
  final jour = iso.substring(0, 10);
  return jour.compareTo(p.debut) >= 0 && jour.compareTo(p.fin) <= 0;
}

/// La date [iso] est-elle antérieure ou égale à la fin de la période ?
/// Sert aux arrêtés : créances et dettes à une date donnée.
bool jusquaPeriode(String? iso, Periode? p) {
  if (p == null) return true;
  if (iso == null || iso.length < 10) return false;
  return iso.substring(0, 10).compareTo(p.fin) <= 0;
}

// ─── Factures & versements ────────────────────────────────────────────────────
// Le statut d'une facture se déduit des versements, il ne se choisit pas — voir
// le getter `Facture.statut`, qui appelle `statutFacture` ci-dessous.

/// Somme des versements reçus sur une facture.
int montantPaye(Facture f) =>
    f.paiements.fold<int>(0, (s, p) => s + p.montant);

/// Ce que le client doit encore. Jamais négatif : un trop-perçu se lit à part.
int resteDu(Facture f) => max(0, f.montantTTC - montantPaye(f));

/// Trop-perçu éventuel : le client a versé plus que le montant de la facture.
/// Cela arrive avec les acomptes arrondis ; on le montre au lieu de l'absorber
/// en silence, car c'est de l'argent qu'on lui doit.
int tropPercu(Facture f) => max(0, montantPaye(f) - f.montantTTC);

/// Le statut se déduit des versements, il ne se saisit pas.
String statutFacture(Facture f) => resteDu(f) == 0 ? 'payée' : 'non payée';

/// Une facture est en retard si elle n'est pas soldée et que l'échéance est
/// passée. Une échéance illisible n'est jamais « en retard » : on n'invente pas
/// une dette sur une date qu'on ne sait pas lire.
bool enRetard(Facture f, [DateTime? maintenant]) {
  if (statutFacture(f) == 'payée') return false;
  final echeance = DateTime.tryParse(f.dateEcheance);
  if (echeance == null) return false;
  return echeance.isBefore(maintenant ?? DateTime.now());
}

/// Total encore dû par un client, toutes factures confondues.
/// [clientId] omis, c'est la créance du magasin entier.
int soldeClient(List<Facture> factures, [String? clientId]) => factures
    .where((f) => clientId == null || f.clientId == clientId)
    .fold<int>(0, (s, f) => s + resteDu(f));

/// Ce que l'on doit au client (trop-perçus cumulés).
int avoirClient(List<Facture> factures, [String? clientId]) => factures
    .where((f) => clientId == null || f.clientId == clientId)
    .fold<int>(0, (s, f) => s + tropPercu(f));

// ─── Dépenses & règlements ────────────────────────────────────────────────────
// Mêmes règles que pour les factures clients, dans l'autre sens : le statut se
// déduit des règlements, il ne se saisit pas.

/// Somme des règlements déjà versés au bénéficiaire.
int montantRegle(Depense d) =>
    d.reglements.fold<int>(0, (s, r) => s + r.montant);

/// Ce qu'on doit encore au fournisseur. Jamais négatif.
int resteAPayer(Depense d) => max(0, d.montant - montantRegle(d));

/// Un trop-versé au fournisseur : de l'argent qu'il nous doit.
int tropVerse(Depense d) => max(0, montantRegle(d) - d.montant);

String statutDepense(Depense d) {
  final regle = montantRegle(d);
  if (regle >= d.montant) return 'réglée';
  return regle > 0 ? 'partielle' : 'non réglée';
}

/// Le délai au-delà duquel une dépense non soldée est signalée en retard.
const _delaiRetardDepense = Duration(days: 30);

/// Une dépense est en retard si elle n'est pas soldée et date de plus de 30
/// jours. Comme pour les factures, une date illisible n'est jamais en retard.
bool depenseEnRetard(Depense d, [DateTime? maintenant]) {
  if (statutDepense(d) == 'réglée') return false;
  final engagee = DateTime.tryParse(d.date);
  if (engagee == null) return false;
  return (maintenant ?? DateTime.now()).difference(engagee) >
      _delaiRetardDepense;
}

// ─── Stock & coût d'achat ─────────────────────────────────────────────────────

/// Coût d'achat des marchandises vendues sur une vente (le « CAMV »).
///
/// Il est estimé au prix d'achat ACTUEL de chaque article, faute d'un prix
/// d'achat historisé ligne à ligne. C'est une approximation, et elle est
/// annoncée comme telle dans l'interface : une marge calculée sur un prix
/// d'achat qui a bougé depuis la vente serait fausse sans qu'on le dise.
///
/// Une ligne dont l'article a été supprimé du catalogue compte pour zéro : on
/// préfère une marge trop belle mais explicable à un coût inventé.
int coutAchatVente(Vente v, Map<String, Article> articlesParId) => v.lignes
    .fold<int>(0, (s, l) => s + (articlesParId[l.articleId]?.prixAchat ?? 0) * l.qte);

/// Marge brute d'une vente : ce qu'elle rapporte, coût d'achat déduit.
int margeVente(Vente v, Map<String, Article> articlesParId) =>
    v.totalNet - coutAchatVente(v, articlesParId);

/// État du stock d'un article. Un stock négatif — que seul un ajustement
/// erroné peut produire — est une rupture : il n'y a rien à vendre.
String stockStatut(Article a) {
  if (a.stock <= 0) return 'rupture';
  if (a.stock < a.stockMin) return 'faible';
  return 'en-stock';
}

/// Valeur du stock au prix d'achat : ce que la marchandise en dépôt a coûté.
int valeurStockAchat(List<Article> articles) =>
    articles.fold<int>(0, (s, a) => s + a.stock * a.prixAchat);

/// Valeur du stock au prix de vente : ce qu'il rapporterait s'il partait entier.
int valeurStockVente(List<Article> articles) =>
    articles.fold<int>(0, (s, a) => s + a.stock * a.prixVente);

// ─── Trésorerie ───────────────────────────────────────────────────────────────

/// Ce qui est réellement passé par la caisse depuis l'origine : tout ce que les
/// clients ont versé, moins tout ce qui est sorti pour régler des dépenses.
///
/// C'est un CUMUL DE MOUVEMENTS, pas un solde de coffre. Il ne connaît ni le
/// fonds de caisse du premier jour, ni ce que le gérant a pu prélever pour lui :
/// ces deux montants ne sont enregistrés nulle part. Il répond exactement à la
/// question « combien d'argent l'activité a-t-elle fait entrer net ? », et c'est
/// à ce titre qu'il est affiché.
///
/// Les factures non réglées et les dépenses non payées n'y figurent pas : elles
/// n'ont pas bougé un franc. Elles se lisent dans `creancesClients` et
/// `dettesFournisseurs` du [Bilan].
///
/// Défini à partir de [calculerBilan] et non recalculé à côté : le tableau de
/// bord et la page Finances doivent annoncer le même chiffre, et deux additions
/// écrites séparément finissent toujours par diverger.
int tresorerieNette({
  required List<Facture> factures,
  required List<Depense> depenses,
  Periode? periode,
}) =>
    calculerBilan(
      ventes: const [],
      factures: factures,
      depenses: depenses,
      articles: const [],
      periode: periode,
    ).fluxTresorerie;

// ─── Compte de résultat & trésorerie ──────────────────────────────────────────

class LigneCategorie {
  final String categorie;
  final String nature;

  /// Montant engagé sur la période (dépenses datées dans la période).
  int engage;

  /// Montant réellement sorti de la caisse sur la période.
  int decaisse;
  int nombre;

  LigneCategorie({
    required this.categorie,
    required this.nature,
    this.engage = 0,
    this.decaisse = 0,
    this.nombre = 0,
  });
}

class Bilan {
  // ── Activité (comptabilité d'engagement) ──
  /// Ventes de la période, net de remises. Le magasin ne facture pas de TVA.
  final int chiffreAffaires;

  /// Coût d'achat des marchandises vendues, estimé au prix d'achat actuel.
  final int coutMarchandises;
  final int margeBrute;

  /// Marge brute en % du chiffre d'affaires. `null` si aucune vente.
  final double? tauxMarge;

  /// Charges d'exploitation engagées sur la période (hors achats et
  /// investissements).
  final int chargesExploitation;

  /// Marge brute − charges d'exploitation. C'est le vrai résultat du commerce.
  final int resultatExploitation;

  // ── Trésorerie (comptabilité de caisse : ce qui bouge vraiment) ──
  /// Versements clients encaissés sur la période.
  final int encaissements;

  /// Règlements de dépenses effectivement sortis sur la période, toutes natures.
  final int decaissements;
  final int fluxTresorerie;

  // ── Hors résultat, mais bien sortis de la caisse ──
  final int achatsMarchandises;
  final int investissements;

  // ── Ce qui reste dehors, à la date de fin de période ──
  /// Argent que les clients nous doivent (factures non soldées).
  final int creancesClients;

  /// Argent que nous devons aux fournisseurs (dépenses non réglées).
  final int dettesFournisseurs;

  /// Créances − dettes : la position nette hors caisse.
  final int positionNette;

  // ── Détails ──
  final List<LigneCategorie> parCategorie;
  final int nbVentes;
  final int nbDepenses;

  const Bilan({
    required this.chiffreAffaires,
    required this.coutMarchandises,
    required this.margeBrute,
    required this.tauxMarge,
    required this.chargesExploitation,
    required this.resultatExploitation,
    required this.encaissements,
    required this.decaissements,
    required this.fluxTresorerie,
    required this.achatsMarchandises,
    required this.investissements,
    required this.creancesClients,
    required this.dettesFournisseurs,
    required this.positionNette,
    required this.parCategorie,
    required this.nbVentes,
    required this.nbDepenses,
  });
}

/// Le compte de résultat et la trésorerie de la période, calculés à partir des
/// seules pièces réelles : ventes enregistrées, versements encaissés, dépenses
/// saisies et règlements effectués. Rien n'est extrapolé, rien n'est projeté.
///
/// Deux lectures cohabitent volontairement et ne doivent JAMAIS être
/// additionnées :
///
///   — le résultat (marge brute − charges d'exploitation) dit si le commerce
///     gagne de l'argent, indépendamment de qui a payé quand ;
///   — la trésorerie (encaissements − décaissements) dit ce qu'il y a dans la
///     caisse. On peut être bénéficiaire et sans un franc si les clients n'ont
///     pas payé ; c'est exactement ce que ces deux blocs séparent.
///
/// Les achats de marchandises et les investissements sortent de la caisse et
/// figurent donc dans la trésorerie, mais pas dans le résultat : le stock acheté
/// n'est pas perdu, il est en dépôt, et il entrera dans le résultat au moment de
/// sa vente via le coût d'achat des marchandises vendues.
///
/// [periode] omise, le bilan porte sur tout l'historique.
Bilan calculerBilan({
  required List<Vente> ventes,
  required List<Facture> factures,
  required List<Depense> depenses,
  required List<Article> articles,
  Periode? periode,
}) {
  final parId = {for (final a in articles) a.id: a};

  final ventesPeriode =
      ventes.where((v) => dansPeriode(v.date, periode)).toList();
  final chiffreAffaires = ventesPeriode.fold<int>(0, (s, v) => s + v.totalNet);
  final coutMarchandises =
      ventesPeriode.fold<int>(0, (s, v) => s + coutAchatVente(v, parId));
  final margeBrute = chiffreAffaires - coutMarchandises;

  // Dépenses engagées sur la période, ventilées par nature.
  final depensesPeriode =
      depenses.where((d) => dansPeriode(d.date, periode)).toList();
  var chargesExploitation = 0, achatsMarchandises = 0, investissements = 0;
  for (final d in depensesPeriode) {
    switch (natureDe(d.categorie)) {
      case 'exploitation':
        chargesExploitation += d.montant;
      case 'marchandise':
        achatsMarchandises += d.montant;
      default:
        investissements += d.montant;
    }
  }

  // Trésorerie : on ne regarde plus la date de la pièce mais celle du mouvement
  // d'argent. Un versement de janvier sur une facture de décembre est une
  // recette de janvier.
  final encaissements = factures.fold<int>(
      0,
      (s, f) =>
          s +
          f.paiements.fold<int>(
              0, (t, p) => t + (dansPeriode(p.date, periode) ? p.montant : 0)));
  final decaissements = depenses.fold<int>(
      0,
      (s, d) =>
          s +
          d.reglements.fold<int>(
              0, (t, r) => t + (dansPeriode(r.date, periode) ? r.montant : 0)));

  // Créances et dettes : un état arrêté à la fin de la période, pas un flux.
  //
  // Deux filtres, et il faut les deux : on ne retient que les pièces émises
  // jusqu'à cette date, ET on ne déduit que les versements reçus jusqu'à cette
  // date. Oublier le second ferait disparaître d'une créance de juillet un
  // versement encaissé en août — au 31 juillet, le client devait encore
  // l'argent, et l'arrêté doit le dire.
  final creancesClients = factures
      .where((f) => jusquaPeriode(f.dateEmission, periode))
      .fold<int>(
          0,
          (s, f) =>
              s +
              max(
                  0,
                  f.montantTTC -
                      f.paiements.fold<int>(
                          0,
                          (t, p) => t +
                              (jusquaPeriode(p.date, periode) ? p.montant : 0))));
  final dettesFournisseurs = depenses
      .where((d) => jusquaPeriode(d.date, periode))
      .fold<int>(
          0,
          (s, d) =>
              s +
              max(
                  0,
                  d.montant -
                      d.reglements.fold<int>(
                          0,
                          (t, r) => t +
                              (jusquaPeriode(r.date, periode) ? r.montant : 0))));

  // Ventilation par catégorie : engagé d'un côté, réellement décaissé de l'autre.
  final parCle = <String, LigneCategorie>{};
  LigneCategorie ligne(String categorie) => parCle.putIfAbsent(categorie,
      () => LigneCategorie(categorie: categorie, nature: natureDe(categorie)));

  for (final d in depensesPeriode) {
    final l = ligne(d.categorie);
    l.engage += d.montant;
    l.nombre++;
  }
  for (final d in depenses) {
    final paye = d.reglements.fold<int>(
        0, (t, r) => t + (dansPeriode(r.date, periode) ? r.montant : 0));
    if (paye > 0) ligne(d.categorie).decaisse += paye;
  }
  final categories = parCle.values.toList()
    ..sort((a, b) =>
        b.engage != a.engage ? b.engage - a.engage : b.decaisse - a.decaisse);

  return Bilan(
    chiffreAffaires: chiffreAffaires,
    coutMarchandises: coutMarchandises,
    margeBrute: margeBrute,
    tauxMarge: chiffreAffaires > 0 ? margeBrute / chiffreAffaires * 100 : null,
    chargesExploitation: chargesExploitation,
    resultatExploitation: margeBrute - chargesExploitation,
    encaissements: encaissements,
    decaissements: decaissements,
    fluxTresorerie: encaissements - decaissements,
    achatsMarchandises: achatsMarchandises,
    investissements: investissements,
    creancesClients: creancesClients,
    dettesFournisseurs: dettesFournisseurs,
    positionNette: creancesClients - dettesFournisseurs,
    parCategorie: categories,
    nbVentes: ventesPeriode.length,
    nbDepenses: depensesPeriode.length,
  );
}
