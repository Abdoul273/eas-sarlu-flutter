import '../auth/droits.dart';
import '../finance/finance_engine.dart';

// ─── Modèles métier ───────────────────────────────────────────────────────────
// Transposition de `src/lib/types.ts` de l'application web, avec la
// normalisation de `src/lib/finance.ts` et `src/lib/inventaire.ts` appliquée
// dès la lecture du JSON.
//
// Deux principes, et ils tiennent tout le reste :
//
//   1. Ce qui se DÉDUIT n'est jamais stocké. Le statut d'une facture, le statut
//      et la nature d'une dépense sont des getters : aucun appelant ne peut leur
//      faire dire autre chose que ce que disent les versements et la catégorie.
//      Ils restent écrits dans `toJson`, parce que le serveur et l'application
//      web portent ces champs.
//
//   2. La normalisation se fait AU BORD, dans les `fromJson`. Toutes les
//      données entrent par là — synchronisation, cache local, restauration —
//      donc aucun chemin ne peut introduire un enregistrement mal formé.
//
// Le moteur de calcul est réexporté : une page qui manipule ces modèles a
// besoin des règles qui vont avec, et il n'y a qu'un seul endroit où elles
// vivent.
export '../auth/droits.dart';
export '../finance/finance_engine.dart';

/// Lit un montant ou une quantité venue du serveur.
///
/// L'application web ne stocke pas des entiers : un total de ligne y vaut
/// `prixVente × qte × (1 − remise/100)` sans arrondi, et c'est à l'affichage
/// qu'elle arrondit. Tronquer ici — ce que fait `toInt()` — ferait afficher
/// 128 333 au téléphone là où le navigateur affiche 128 334. On arrondit donc,
/// exactement comme le `Math.round` du web.
int _entier(dynamic v) => (v as num?)?.round() ?? 0;

double _decimal(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

// --- Modèles métier (tous avec rev, updatedAt, updatedBy) ---

class Article {
  final String id;
  final String ref;
  final String nom;
  final String categorie;
  final String description;
  final String unite;
  final int prixAchat;
  final int prixVente;
  final int stock;
  final int stockMin;
  final String fournisseur;
  final String photo;
  final double? longueur; // mètres (6 ou 12)

  /// Épaisseur en mm (2, 3, 0,45…) — ce que le magasin demande.
  ///
  /// Jamais nulle. Les articles enregistrés avant le passage à l'épaisseur
  /// portaient un `poidsBarre` en kilos : ce nombre n'est **pas** converti —
  /// 31,4 kg n'est pas une épaisseur — il est abandonné, et l'épaisseur part à
  /// zéro. La fiche de l'article la réclamera à la première modification. Sans
  /// cela, l'écran affichait « null mm » sur tout l'ancien stock.
  final double epaisseur;
  final String provenance;
  // Métadonnées de synchronisation
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Article({
    required this.id,
    this.ref = '',
    required this.nom,
    this.categorie = '',
    this.description = '',
    required this.unite,
    this.prixAchat = 0,
    this.prixVente = 0,
    this.stock = 0,
    this.stockMin = 0,
    this.fournisseur = '',
    this.photo = '',
    this.longueur,
    this.epaisseur = 0,
    this.provenance = '',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id'] as String? ?? '',
      ref: json['ref'] as String? ?? '',
      nom: json['nom'] as String? ?? '',
      categorie: json['categorie'] as String? ?? '',
      description: json['description'] as String? ?? '',
      unite: json['unite'] as String? ?? '',
      prixAchat: _entier(json['prixAchat']),
      prixVente: _entier(json['prixVente']),
      // Un stock négatif n'a pas de sens physique : il ne peut venir que
      // d'une écriture qui a contourné les règles. Borné ici, il ne
      // s'affichera plus nulle part — et le serveur borne de même.
      stock: _entier(json['stock']) < 0 ? 0 : _entier(json['stock']),
      stockMin: _entier(json['stockMin']),
      fournisseur: json['fournisseur'] as String? ?? '',
      photo: json['photo'] as String? ?? '',
      longueur: (json['longueur'] as num?)?.toDouble(),
      // `poidsBarre` des anciens articles est volontairement ignoré : il est en
      // kilos, pas en millimètres. L'épaisseur repart de zéro.
      epaisseur: _decimal(json['epaisseur']),
      provenance: json['provenance'] as String? ?? '',
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ref': ref,
      'nom': nom,
      'categorie': categorie,
      'description': description,
      'unite': unite,
      'prixAchat': prixAchat,
      'prixVente': prixVente,
      'stock': stock,
      'stockMin': stockMin,
      'fournisseur': fournisseur,
      'photo': photo,
      if (longueur != null) 'longueur': longueur,
      'epaisseur': epaisseur,
      'provenance': provenance,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }

  Article copyWith({
    String? id,
    String? ref,
    String? nom,
    String? categorie,
    String? description,
    String? unite,
    int? prixAchat,
    int? prixVente,
    int? stock,
    int? stockMin,
    String? fournisseur,
    String? photo,
    double? longueur,
    double? epaisseur,
    String? provenance,
    int? rev,
    String? updatedAt,
    String? updatedBy,
  }) {
    return Article(
      id: id ?? this.id,
      ref: ref ?? this.ref,
      nom: nom ?? this.nom,
      categorie: categorie ?? this.categorie,
      description: description ?? this.description,
      unite: unite ?? this.unite,
      prixAchat: prixAchat ?? this.prixAchat,
      prixVente: prixVente ?? this.prixVente,
      stock: stock ?? this.stock,
      stockMin: stockMin ?? this.stockMin,
      fournisseur: fournisseur ?? this.fournisseur,
      photo: photo ?? this.photo,
      longueur: longueur ?? this.longueur,
      epaisseur: epaisseur ?? this.epaisseur,
      provenance: provenance ?? this.provenance,
      rev: rev ?? this.rev,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

class MouvementStock {
  final String id;
  final String articleId;
  final String type; // entrée, sortie, ajustement
  final int quantite;
  final int? quantiteAvant;
  final int? quantiteApres;
  final String date; // ISO 8601
  final String utilisateur;
  final String note;
  final String? fournisseurId;
  final String? fournisseurNom;
  final String? fournisseurQuartier;
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  MouvementStock({
    required this.id,
    required this.articleId,
    required this.type,
    required this.quantite,
    this.quantiteAvant,
    this.quantiteApres,
    required this.date,
    this.utilisateur = '',
    this.note = '',
    this.fournisseurId,
    this.fournisseurNom,
    this.fournisseurQuartier,
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  factory MouvementStock.fromJson(Map<String, dynamic> json) {
    return MouvementStock(
      id: json['id'] as String? ?? '',
      articleId: json['articleId'] as String? ?? '',
      type: json['type'] as String? ?? '',
      quantite: _entier(json['quantite']),
      quantiteAvant: (json['quantiteAvant'] as num?)?.round(),
      quantiteApres: (json['quantiteApres'] as num?)?.round(),
      date: json['date'] as String? ?? '',
      utilisateur: json['utilisateur'] as String? ?? '',
      note: json['note'] as String? ?? '',
      fournisseurId: json['fournisseurId'] as String?,
      fournisseurNom: json['fournisseurNom'] as String?,
      fournisseurQuartier: json['fournisseurQuartier'] as String?,
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'articleId': articleId,
      'type': type,
      'quantite': quantite,
      if (quantiteAvant != null) 'quantiteAvant': quantiteAvant,
      if (quantiteApres != null) 'quantiteApres': quantiteApres,
      'date': date,
      'utilisateur': utilisateur,
      'note': note,
      if (fournisseurId != null) 'fournisseurId': fournisseurId,
      if (fournisseurNom != null) 'fournisseurNom': fournisseurNom,
      if (fournisseurQuartier != null) 'fournisseurQuartier': fournisseurQuartier,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }
}

class LigneVente {
  final String articleId;
  final String articleRef;
  final String articleNom;
  final String unite;
  final int qte;
  final int prixUnitaire;

  /// Remise de ligne, en pourcentage. Le magasin n'en accorde pas et
  /// l'application Android n'en fait pas saisir : elle vaut zéro sur toute
  /// vente encaissée au téléphone. Elle est en revanche lue fidèlement — et en
  /// décimal, car l'application web permet d'écrire 15,5 % — pour qu'une vente
  /// venue du navigateur s'affiche telle qu'elle a été faite.
  final double remise;
  final int total;

  /// Le prix d'achat unitaire de l'article AU MOMENT de la vente.
  ///
  /// Figé ici, comme `prixUnitaire` : la marge d'une vente de mars ne doit pas
  /// changer parce que le fer a augmenté en juin. `null` sur les ventes
  /// antérieures à ce champ — le calcul retombe alors sur le prix d'achat
  /// courant de l'article, et le dit.
  final int? prixAchat;

  LigneVente({
    required this.articleId,
    this.articleRef = '',
    this.articleNom = '',
    this.unite = '',
    required this.qte,
    required this.prixUnitaire,
    this.remise = 0,
    this.total = 0,
    this.prixAchat,
  });

  factory LigneVente.fromJson(Map<String, dynamic> json) {
    final pa = json['prixAchat'];
    return LigneVente(
      articleId: json['articleId'] as String? ?? '',
      articleRef: json['articleRef'] as String? ?? '',
      articleNom: json['articleNom'] as String? ?? '',
      unite: json['unite'] as String? ?? '',
      qte: _entier(json['qte']),
      prixUnitaire: _entier(json['prixUnitaire']),
      remise: borneRemise(json['remise'] as num?),
      total: _entier(json['total']),
      prixAchat: pa is num ? pa.round() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'articleId': articleId,
      'articleRef': articleRef,
      'articleNom': articleNom,
      'unite': unite,
      'qte': qte,
      'prixUnitaire': prixUnitaire,
      'remise': remise,
      'total': total,
      if (prixAchat != null) 'prixAchat': prixAchat,
    };
  }

  /// Ce que la ligne a coûté au magasin : le prix d'achat figé, ou à défaut
  /// le prix courant de l'article. UNE seule règle, pour que le rapport,
  /// l'assistant et le compte de résultat annoncent la même marge.
  int coutAchat(Article? article) => (prixAchat ?? article?.prixAchat ?? 0) * qte;
}

class Vente {
  final String id;
  final String numero; // peut être vide en local, renseigné par le serveur
  final String clientId;
  final String vendeur;
  final String date;
  final List<LigneVente> lignes;

  /// Remise globale sur la vente, en pourcentage. Voir `LigneVente.remise` :
  /// toujours nulle au téléphone, lue fidèlement quand elle vient du web.
  final double remiseGlobale;
  final int totalHT;
  final int totalNet;
  final String note;
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Vente({
    required this.id,
    this.numero = '',
    required this.clientId,
    this.vendeur = '',
    required this.date,
    this.lignes = const [],
    this.remiseGlobale = 0,
    this.totalHT = 0,
    this.totalNet = 0,
    this.note = '',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  Vente copyWith({
    String? id,
    String? numero,
    String? clientId,
    String? vendeur,
    String? date,
    List<LigneVente>? lignes,
    double? remiseGlobale,
    int? totalHT,
    int? totalNet,
    String? note,
    int? rev,
    String? updatedAt,
    String? updatedBy,
  }) {
    return Vente(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      clientId: clientId ?? this.clientId,
      vendeur: vendeur ?? this.vendeur,
      date: date ?? this.date,
      lignes: lignes ?? this.lignes,
      remiseGlobale: remiseGlobale ?? this.remiseGlobale,
      totalHT: totalHT ?? this.totalHT,
      totalNet: totalNet ?? this.totalNet,
      note: note ?? this.note,
      rev: rev ?? this.rev,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  factory Vente.fromJson(Map<String, dynamic> json) {
    return Vente(
      id: json['id'] as String? ?? '',
      numero: json['numero'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      vendeur: json['vendeur'] as String? ?? '',
      date: json['date'] as String? ?? '',
      lignes: (json['lignes'] as List<dynamic>?)
              ?.map((e) => LigneVente.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      remiseGlobale: borneRemise(json['remiseGlobale'] as num?),
      totalHT: _entier(json['totalHT']),
      totalNet: _entier(json['totalNet']),
      note: json['note'] as String? ?? '',
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero': numero,
      'clientId': clientId,
      'vendeur': vendeur,
      'date': date,
      'lignes': lignes.map((l) => l.toJson()).toList(),
      'remiseGlobale': remiseGlobale,
      'totalHT': totalHT,
      'totalNet': totalNet,
      'note': note,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }
}

class Paiement {
  final String id;
  final String date; // ISO 8601
  final int montant;
  final String mode; // espèces, mobile money, virement, chèque
  final String note;
  final String utilisateur;

  Paiement({
    required this.id,
    required this.date,
    required this.montant,
    this.mode = 'espèces',
    this.note = '',
    this.utilisateur = '',
  });

  factory Paiement.fromJson(Map<String, dynamic> json) {
    return Paiement(
      id: json['id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      montant: _entier(json['montant']),
      mode: json['mode'] as String? ?? 'espèces',
      note: json['note'] as String? ?? '',
      utilisateur: json['utilisateur'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'montant': montant,
      'mode': mode,
      'note': note,
      'utilisateur': utilisateur,
    };
  }
}

class Facture {
  final String id;
  final String numero;
  final String venteId;
  final String clientId;
  final String dateEmission;
  final String dateEcheance;
  final int montantHT;
  final double tauxTVA;
  final int montantTVA;
  final int montantTTC;
  final double remise;
  final String note;

  /// Versements reçus, du plus ancien au plus récent.
  final List<Paiement> paiements;
  final String creePar;

  /// Déduit des versements, jamais choisi. Une facture est soldée quand il ne
  /// reste rien à devoir — pas quand quelqu'un a coché « payée ».
  String get statut => statutFacture(this);
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Facture({
    required this.id,
    this.numero = '',
    required this.venteId,
    required this.clientId,
    required this.dateEmission,
    this.dateEcheance = '',
    this.montantHT = 0,
    this.tauxTVA = 0.0,
    this.montantTVA = 0,
    this.montantTTC = 0,
    this.remise = 0,
    this.note = '',
    this.paiements = const [],
    this.creePar = '',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  factory Facture.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final dateEmission = json['dateEmission'] as String? ?? '';
    final montantTTC = _entier(json['montantTTC']);
    final creePar = json['creePar'] as String? ?? '';
    final paiements = (json['paiements'] as List<dynamic>?)
            ?.map((e) => Paiement.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <Paiement>[];

    // Les anciennes factures portaient « payée », « en attente » ou « en
    // retard » et n'avaient aucun versement enregistré. Sans cette reprise,
    // une facture soldée depuis des mois redeviendrait une créance dès qu'elle
    // est lue ici : le solde du client sur le téléphone ne dirait plus la même
    // chose que celui du navigateur. Une facture marquée « payée » à l'époque
    // est donc considérée soldée, les autres restent dues.
    final ancienneSoldee = paiements.isEmpty && json['statut'] == 'payée';

    return Facture(
      id: id,
      numero: json['numero'] as String? ?? '',
      venteId: json['venteId'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      dateEmission: dateEmission,
      dateEcheance: json['dateEcheance'] as String? ?? '',
      montantHT: _entier(json['montantHT']),
      tauxTVA: _decimal(json['tauxTVA']),
      montantTVA: _entier(json['montantTVA']),
      montantTTC: montantTTC,
      remise: borneRemise(json['remise'] as num?),
      note: json['note'] as String? ?? '',
      paiements: ancienneSoldee
          ? [
              Paiement(
                id: 'PAY_MIGR_$id',
                date: dateEmission.isNotEmpty
                    ? dateEmission
                    : DateTime.now().toIso8601String(),
                montant: montantTTC,
                mode: 'espèces',
                note: 'Règlement antérieur au suivi des versements',
                utilisateur: creePar,
              )
            ]
          : paiements,
      creePar: creePar,
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero': numero,
      'venteId': venteId,
      'clientId': clientId,
      'dateEmission': dateEmission,
      'dateEcheance': dateEcheance,
      'montantHT': montantHT,
      'tauxTVA': tauxTVA,
      'montantTVA': montantTVA,
      'montantTTC': montantTTC,
      'remise': remise,
      'note': note,
      'statut': statut,
      'paiements': paiements.map((p) => p.toJson()).toList(),
      'creePar': creePar,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }

  Facture copyWith({
    String? id,
    String? numero,
    String? venteId,
    String? clientId,
    String? dateEmission,
    String? dateEcheance,
    int? montantHT,
    double? tauxTVA,
    int? montantTVA,
    int? montantTTC,
    double? remise,
    String? note,
    List<Paiement>? paiements,
    String? creePar,
    int? rev,
    String? updatedAt,
    String? updatedBy,
  }) {
    return Facture(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      venteId: venteId ?? this.venteId,
      clientId: clientId ?? this.clientId,
      dateEmission: dateEmission ?? this.dateEmission,
      dateEcheance: dateEcheance ?? this.dateEcheance,
      montantHT: montantHT ?? this.montantHT,
      tauxTVA: tauxTVA ?? this.tauxTVA,
      montantTVA: montantTVA ?? this.montantTVA,
      montantTTC: montantTTC ?? this.montantTTC,
      remise: remise ?? this.remise,
      note: note ?? this.note,
      paiements: paiements ?? this.paiements,
      creePar: creePar ?? this.creePar,
      rev: rev ?? this.rev,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  /// Retourne une copie de la facture avec un paiement ajouté (sans muter la liste).
  Facture avecPaiement(Paiement paiement) {
    return copyWith(paiements: [...paiements, paiement]);
  }
}

class Client {
  final String id;
  final String nom;
  final String type; // professionnel, particulier
  final String email;
  final String telephone;
  final String adresse;
  final String quartier;
  final String ville;
  final String creeLe;
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Client({
    required this.id,
    required this.nom,
    this.type = 'particulier',
    this.email = '',
    this.telephone = '',
    this.adresse = '',
    this.quartier = '',
    this.ville = '',
    this.creeLe = '',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['id'] as String? ?? '',
      nom: json['nom'] as String? ?? '',
      type: json['type'] as String? ?? 'particulier',
      email: json['email'] as String? ?? '',
      telephone: json['telephone'] as String? ?? '',
      adresse: json['adresse'] as String? ?? '',
      quartier: json['quartier'] as String? ?? '',
      ville: json['ville'] as String? ?? '',
      creeLe: json['creeLe'] as String? ?? '',
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nom': nom,
      'type': type,
      'email': email,
      'telephone': telephone,
      'adresse': adresse,
      'quartier': quartier,
      'ville': ville,
      'creeLe': creeLe,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }

  Client copyWith({
    String? id,
    String? nom,
    String? type,
    String? email,
    String? telephone,
    String? adresse,
    String? quartier,
    String? ville,
    String? creeLe,
    int? rev,
    String? updatedAt,
    String? updatedBy,
  }) {
    return Client(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      type: type ?? this.type,
      email: email ?? this.email,
      telephone: telephone ?? this.telephone,
      adresse: adresse ?? this.adresse,
      quartier: quartier ?? this.quartier,
      ville: ville ?? this.ville,
      creeLe: creeLe ?? this.creeLe,
      rev: rev ?? this.rev,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

class Fournisseur {
  final String id;
  final String nom;
  final String telephone;
  final String email;
  final String adresse;
  final String quartier;
  final String ville;
  final String creeLe;
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Fournisseur({
    required this.id,
    required this.nom,
    this.telephone = '',
    this.email = '',
    this.adresse = '',
    this.quartier = '',
    this.ville = '',
    this.creeLe = '',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  factory Fournisseur.fromJson(Map<String, dynamic> json) {
    return Fournisseur(
      id: json['id'] as String? ?? '',
      nom: json['nom'] as String? ?? '',
      telephone: json['telephone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      adresse: json['adresse'] as String? ?? '',
      quartier: json['quartier'] as String? ?? '',
      ville: json['ville'] as String? ?? '',
      creeLe: json['creeLe'] as String? ?? '',
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nom': nom,
      'telephone': telephone,
      'email': email,
      'adresse': adresse,
      'quartier': quartier,
      'ville': ville,
      'creeLe': creeLe,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }

  Fournisseur copyWith({
    String? id,
    String? nom,
    String? telephone,
    String? email,
    String? adresse,
    String? quartier,
    String? ville,
    String? creeLe,
    int? rev,
    String? updatedAt,
    String? updatedBy,
  }) {
    return Fournisseur(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      adresse: adresse ?? this.adresse,
      quartier: quartier ?? this.quartier,
      ville: ville ?? this.ville,
      creeLe: creeLe ?? this.creeLe,
      rev: rev ?? this.rev,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

// ─── Proforma ─────────────────────────────────────────────────────────────────
// Le papier qu'on tend au client pour qu'il réfléchisse : chiffré, daté,
// valable quelques jours, sans effet sur le stock ni la caisse. Le serveur le
// range sous le type « devis » et lui attribue son numéro PRO-AAAA-NNNN.

/// Ce qu'une proforma peut être.
abstract final class StatutProforma {
  static const envoyee = 'envoye';
  static const acceptee = 'accepte';
  static const refusee = 'refuse';
  static const convertie = 'converti';

  static String libelle(String s) => switch (s) {
        envoyee => 'Envoyée',
        acceptee => 'Acceptée',
        refusee => 'Refusée',
        convertie => 'Vendue',
        'expire' => 'Expirée',
        _ => 'Brouillon',
      };
}

class Proforma {
  final String id;

  /// Vide tant que le serveur ne l'a pas attribué.
  final String numero;
  final String clientId;

  /// Le nom tapé quand le client n'est pas dans le fichier.
  final String clientNom;
  final String date;
  final int validiteJours;
  final List<LigneVente> lignes;
  final int totalNet;
  final String note;
  final String statut;

  /// La vente qui en est sortie, une fois convertie.
  final String venteId;
  final String creePar;
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Proforma({
    required this.id,
    this.numero = '',
    this.clientId = '',
    this.clientNom = '',
    required this.date,
    this.validiteJours = 15,
    this.lignes = const [],
    this.totalNet = 0,
    this.note = '',
    this.statut = StatutProforma.envoyee,
    this.venteId = '',
    this.creePar = '',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  DateTime? get dateValeur => DateTime.tryParse(date);
  DateTime? get valableJusquA =>
      dateValeur?.add(Duration(days: validiteJours));

  /// Expirée : encore ouverte, mais la date de validité est passée.
  bool get expiree =>
      statut == StatutProforma.envoyee &&
      (valableJusquA?.isBefore(DateTime.now()) ?? false);

  /// Le statut tel qu'il se lit, expiration comprise.
  String get statutEffectif => expiree ? 'expire' : statut;

  /// Une proforma se transforme en vente tant qu'elle n'a pas été vendue ni
  /// refusée — même expirée : le client qui revient en retard reste un client.
  bool get convertible =>
      statut == StatutProforma.envoyee || statut == StatutProforma.acceptee;

  factory Proforma.fromJson(Map<String, dynamic> json) {
    return Proforma(
      id: json['id'] as String? ?? '',
      numero: json['numero'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      clientNom: json['clientNom'] as String? ?? '',
      date: json['date'] as String? ?? '',
      validiteJours: _entier(json['validiteJours']) > 0
          ? _entier(json['validiteJours'])
          : 15,
      lignes: (json['lignes'] as List<dynamic>? ?? const [])
          .map((l) => LigneVente.fromJson(l as Map<String, dynamic>))
          .toList(),
      totalNet: _entier(json['totalNet']),
      note: json['note'] as String? ?? '',
      statut: json['statut'] as String? ?? StatutProforma.envoyee,
      venteId: json['venteId'] as String? ?? '',
      creePar: json['creePar'] as String? ?? '',
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'numero': numero,
        'clientId': clientId,
        'clientNom': clientNom,
        'date': date,
        'validiteJours': validiteJours,
        'lignes': lignes.map((l) => l.toJson()).toList(),
        'totalNet': totalNet,
        'note': note,
        'statut': statut,
        'venteId': venteId,
        'creePar': creePar,
        if (rev != null) '_rev': rev,
        if (updatedAt != null) '_updatedAt': updatedAt,
        if (updatedBy != null) '_updatedBy': updatedBy,
      };

  Proforma copyWith({
    String? numero,
    String? clientId,
    String? clientNom,
    List<LigneVente>? lignes,
    int? totalNet,
    String? note,
    String? statut,
    String? venteId,
    int? rev,
  }) =>
      Proforma(
        id: id,
        numero: numero ?? this.numero,
        clientId: clientId ?? this.clientId,
        clientNom: clientNom ?? this.clientNom,
        date: date,
        validiteJours: validiteJours,
        lignes: lignes ?? this.lignes,
        totalNet: totalNet ?? this.totalNet,
        note: note ?? this.note,
        statut: statut ?? this.statut,
        venteId: venteId ?? this.venteId,
        creePar: creePar,
        rev: rev ?? this.rev,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );
}

class Reglement {
  final String id;
  final String date;
  final int montant;
  final String mode;
  final String note;
  final String utilisateur;

  Reglement({
    required this.id,
    required this.date,
    required this.montant,
    this.mode = 'espèces',
    this.note = '',
    this.utilisateur = '',
  });

  factory Reglement.fromJson(Map<String, dynamic> json) {
    return Reglement(
      id: json['id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      montant: _entier(json['montant']),
      mode: json['mode'] as String? ?? 'espèces',
      note: json['note'] as String? ?? '',
      utilisateur: json['utilisateur'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'montant': montant,
      'mode': mode,
      'note': note,
      'utilisateur': utilisateur,
    };
  }
}

class Depense {
  final String id;
  final String numero;
  final String date;
  final String categorie;
  final String libelle;
  final String beneficiaire;
  final int montant;
  final String reference;
  final String note;
  final List<Reglement> reglements;
  final String creePar;

  /// Nature comptable. Toujours recalculée depuis la catégorie : c'est elle qui
  /// fait autorité, pas ce qui a été enregistré un jour où le catalogue était
  /// différent. C'est ce qui garantit qu'un achat de tôle ne sera jamais compté
  /// comme une charge du mois.
  String get nature => natureDe(categorie);

  /// Déduit des règlements, jamais choisi.
  String get statut => statutDepense(this);
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Depense({
    required this.id,
    this.numero = '',
    required this.date,
    this.categorie = 'Divers',
    this.libelle = '',
    this.beneficiaire = '',
    required this.montant,
    this.reference = '',
    this.note = '',
    this.reglements = const [],
    this.creePar = '',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  factory Depense.fromJson(Map<String, dynamic> json) {
    return Depense(
      id: json['id'] as String? ?? '',
      numero: json['numero'] as String? ?? '',
      date: json['date'] as String? ?? '',
      // Une dépense sans catégorie tombe dans « Divers », comme sur le web.
      // `nature` et `statut` du JSON sont volontairement ignorés : ils se
      // déduisent, et une valeur enregistrée jadis n'a pas à contredire la
      // règle d'aujourd'hui.
      categorie: (json['categorie'] as String?)?.isNotEmpty == true
          ? json['categorie'] as String
          : 'Divers',
      libelle: json['libelle'] as String? ?? '',
      beneficiaire: json['beneficiaire'] as String? ?? '',
      montant: _entier(json['montant']),
      reference: json['reference'] as String? ?? '',
      note: json['note'] as String? ?? '',
      reglements: (json['reglements'] as List<dynamic>?)
              ?.map((e) => Reglement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      creePar: json['creePar'] as String? ?? '',
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero': numero,
      'date': date,
      'categorie': categorie,
      'nature': nature,
      'libelle': libelle,
      'beneficiaire': beneficiaire,
      'montant': montant,
      'reference': reference,
      'note': note,
      'reglements': reglements.map((r) => r.toJson()).toList(),
      'statut': statut,
      'creePar': creePar,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }

  Depense copyWith({
    String? id,
    String? numero,
    String? date,
    String? categorie,
    String? libelle,
    String? beneficiaire,
    int? montant,
    String? reference,
    String? note,
    List<Reglement>? reglements,
    String? creePar,
    int? rev,
    String? updatedAt,
    String? updatedBy,
  }) {
    return Depense(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      date: date ?? this.date,
      categorie: categorie ?? this.categorie,
      libelle: libelle ?? this.libelle,
      beneficiaire: beneficiaire ?? this.beneficiaire,
      montant: montant ?? this.montant,
      reference: reference ?? this.reference,
      note: note ?? this.note,
      reglements: reglements ?? this.reglements,
      creePar: creePar ?? this.creePar,
      rev: rev ?? this.rev,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  /// Retourne une copie de la dépense avec un règlement ajouté (sans muter la liste).
  Depense avecReglement(Reglement reglement) {
    return copyWith(reglements: [...reglements, reglement]);
  }
}

class Entreprise {
  final String nom;
  final String slogan;
  final String adresse;
  final String quartier;
  final String ville;
  final String telephone;
  final String email;
  final String siteWeb;
  final String rccm;
  final String nif;
  final String logo;
  final double tauxTVA;
  final String devise;
  final String conditionsPaiement;
  final String mentionsLegales;
  final String signataire;
  final String signatureImage;
  final String rib;
  final String banque;
  final String swift;
  final String couleurAccent;
  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Entreprise({
    this.nom = '',
    this.slogan = '',
    this.adresse = '',
    this.quartier = '',
    this.ville = '',
    this.telephone = '',
    this.email = '',
    this.siteWeb = '',
    this.rccm = '',
    this.nif = '',
    this.logo = '',
    this.tauxTVA = 0.0,
    this.devise = 'GNF',
    this.conditionsPaiement = '',
    this.mentionsLegales = '',
    this.signataire = '',
    this.signatureImage = '',
    this.rib = '',
    this.banque = '',
    this.swift = '',
    this.couleurAccent = '#E85D04',
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  factory Entreprise.fromJson(Map<String, dynamic> json) {
    return Entreprise(
      nom: json['nom'] as String? ?? '',
      slogan: json['slogan'] as String? ?? '',
      adresse: json['adresse'] as String? ?? '',
      quartier: json['quartier'] as String? ?? '',
      ville: json['ville'] as String? ?? '',
      telephone: json['telephone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      siteWeb: json['siteWeb'] as String? ?? '',
      rccm: json['rccm'] as String? ?? '',
      nif: json['nif'] as String? ?? '',
      logo: json['logo'] as String? ?? '',
      tauxTVA: _decimal(json['tauxTVA']),
      devise: json['devise'] as String? ?? 'GNF',
      conditionsPaiement: json['conditionsPaiement'] as String? ?? '',
      mentionsLegales: json['mentionsLegales'] as String? ?? '',
      signataire: json['signataire'] as String? ?? '',
      signatureImage: json['signatureImage'] as String? ?? '',
      rib: json['rib'] as String? ?? '',
      banque: json['banque'] as String? ?? '',
      swift: json['swift'] as String? ?? '',
      couleurAccent: json['couleurAccent'] as String? ?? '#E85D04',
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nom': nom,
      'slogan': slogan,
      'adresse': adresse,
      'quartier': quartier,
      'ville': ville,
      'telephone': telephone,
      'email': email,
      'siteWeb': siteWeb,
      'rccm': rccm,
      'nif': nif,
      'logo': logo,
      'tauxTVA': tauxTVA,
      'devise': devise,
      'conditionsPaiement': conditionsPaiement,
      'mentionsLegales': mentionsLegales,
      'signataire': signataire,
      'signatureImage': signatureImage,
      'rib': rib,
      'banque': banque,
      'swift': swift,
      'couleurAccent': couleurAccent,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }
}

class Utilisateur {
  final String id;
  final String email;
  final String nom;
  final bool actif;
  final String creeLe;

  /// Détient tous les droits en permanence, et peut en nommer d'autres. Il en
  /// existe toujours au moins un : le serveur refuse de retirer, désactiver ou
  /// supprimer le dernier.
  final bool proprietaire;

  /// Ce que le compte a le droit de faire. Un propriétaire les a tous, quoi que
  /// dise cette liste — voir [aLeDroit].
  final List<String> droits;

  final int? rev;
  final String? updatedAt;
  final String? updatedBy;

  Utilisateur({
    required this.id,
    this.email = '',
    required this.nom,
    this.actif = true,
    this.creeLe = '',
    this.proprietaire = false,
    this.droits = const [],
    this.rev,
    this.updatedAt,
    this.updatedBy,
  });

  /// Ce compte a-t-il le droit demandé ?
  ///
  /// Un compte désactivé n'a rien, et un droit inconnu est refusé : on échoue
  /// toujours du côté fermé. C'est aussi ce que fait le serveur.
  bool aLeDroit(String droit) {
    if (!actif) return false;
    // Un droit que l'application ne connaît pas ne s'accorde pas, même s'il
    // figure dans la liste : une sauvegarde ancienne ou un serveur plus récent
    // pourraient en porter, et on ne devine pas ce qu'ils permettent.
    if (!kDroits.containsKey(droit)) return false;
    if (proprietaire) return true;
    return droits.contains(droit);
  }

  /// Les droits effectifs, propriété comprise — ce que l'écran affiche.
  List<String> get droitsEffectifs =>
      proprietaire ? kDroits.keys.toList() : normaliserDroits(droits);

  /// Ancienne forme du droit « prixAchat ». Conservée parce que le serveur
  /// l'émet encore et que des écrans la lisent ; elle en découle strictement.
  bool get voitPrixAchat => aLeDroit('prixAchat');

  factory Utilisateur.fromJson(Map<String, dynamic> json) {
    // `voitPrixAchat` sert de repli pour un serveur pas encore à jour : sans
    // lui, un compte se retrouverait sans aucun droit, donc sans rien pouvoir
    // faire, sur la seule foi d'un champ absent.
    final brut = json['droits'];
    final droits = brut is List
        ? normaliserDroits(brut)
        : (json['voitPrixAchat'] as bool? ?? false ? const ['prixAchat'] : const <String>[]);

    return Utilisateur(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      nom: json['nom'] as String? ?? '',
      actif: json['actif'] as bool? ?? true,
      creeLe: json['creeLe'] as String? ?? '',
      proprietaire: json['proprietaire'] as bool? ?? false,
      droits: droits,
      rev: json['_rev'] as int?,
      updatedAt: json['_updatedAt'] as String?,
      updatedBy: json['_updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'nom': nom,
      'actif': actif,
      'proprietaire': proprietaire,
      'droits': droits,
      // Émis pour rester lisible par les versions qui ne connaissent que lui.
      'voitPrixAchat': voitPrixAchat,
      'creeLe': creeLe,
      if (rev != null) '_rev': rev,
      if (updatedAt != null) '_updatedAt': updatedAt,
      if (updatedBy != null) '_updatedBy': updatedBy,
    };
  }
}
