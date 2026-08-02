// lib/core/models/activite.dart

// ─── Journal d'activité ───────────────────────────────────────────────────────
// Une entrée du journal tenu par le serveur : qui a fait quoi, quand, et sur
// quel objet. C'est la matière première de la page Activité ET du système de
// notifications ; le modèle vit donc dans `core`, au-dessus des deux, plutôt
// que dans l'écran qui s'en est servi le premier.
//
// Tout ce qui se déduit d'une entrée — son intitulé lisible, sa famille, la
// page vers laquelle elle renvoie — est calculé ici, une fois. Chaque écran qui
// refaisait ce `switch` dans son coin finissait par diverger : la liste des
// types de la page Activité en oubliait cinq que le serveur émet réellement.

/// Les types d'activité que le serveur émet, tels qu'ils apparaissent dans
/// `logActivite(...)` (supabase/functions/server/index.tsx).
///
/// La liste est exhaustive et volontairement en dur : une entrée d'un type
/// inconnu reste affichée, mais on veut pouvoir la repérer plutôt que de la
/// classer en silence.
const Map<String, String> kTypesActivite = {
  'vente': 'Ventes',
  'facture': 'Factures et encaissements',
  'depense': 'Dépenses',
  'article': 'Catalogue',
  'prix': 'Changements de prix',
  'mouvement': 'Mouvements de stock',
  'client': 'Clients',
  'utilisateur': 'Comptes',
  'appareil': 'Appareils',
  'parametres': 'Paramètres',
  'sauvegarde': 'Sauvegardes',
};

/// Regroupement pour les notifications : trois canaux Android plutôt qu'onze.
///
/// Onze canaux, c'est un écran de réglages illisible et onze interrupteurs à
/// comprendre. Trois familles suffisent à la seule décision qui compte pour le
/// gérant : « préviens-moi pour l'argent, pas pour le reste ».
enum FamilleActivite {
  /// Ce qui fait bouger la caisse ou la créance : vente, encaissement, dépense.
  argent,

  /// Ce qui fait bouger la marchandise ou le catalogue.
  stock,

  /// Comptes, appareils, paramètres, sauvegardes.
  administration,
}

const Map<String, FamilleActivite> _familleParType = {
  'vente': FamilleActivite.argent,
  'facture': FamilleActivite.argent,
  'depense': FamilleActivite.argent,
  'article': FamilleActivite.stock,
  'prix': FamilleActivite.stock,
  'mouvement': FamilleActivite.stock,
  'client': FamilleActivite.stock,
  'utilisateur': FamilleActivite.administration,
  'appareil': FamilleActivite.administration,
  'parametres': FamilleActivite.administration,
  'sauvegarde': FamilleActivite.administration,
};

/// Intitulé court d'une famille, affiché comme nom de canal Android.
const Map<FamilleActivite, String> kLibelleFamille = {
  FamilleActivite.argent: 'Ventes, encaissements et dépenses',
  FamilleActivite.stock: 'Stock et catalogue',
  FamilleActivite.administration: 'Comptes et administration',
};

/// Titre de la notification, par type. Une notification titrée
/// « Nouvelle activité : DEPENSE » n'apprend rien ; celle-ci dit ce qui vient
/// de se passer avant même qu'on lise le détail.
const Map<String, String> kTitreNotification = {
  'vente': 'Nouvelle vente',
  'facture': 'Facture et encaissement',
  'depense': 'Dépense',
  'article': 'Catalogue modifié',
  'prix': 'Changement de prix',
  'mouvement': 'Mouvement de stock',
  'client': 'Client',
  'utilisateur': 'Compte utilisateur',
  'appareil': 'Appareil',
  'parametres': "Paramètres de l'entreprise",
  'sauvegarde': 'Sauvegarde',
};

class ActiviteEntree {
  final String id;

  /// Type émis par le serveur ; voir [kTypesActivite].
  final String type;
  final String description;
  final String auteur;

  /// Date telle que reçue. Le serveur écrit tantôt une chaîne ISO, tantôt un
  /// horodatage en millisecondes — les deux se lisent, voir [dateTime].
  final String date;

  /// L'entrée provient d'une opération rejouée depuis la file hors ligne.
  final bool horsLigne;

  /// Objet visé par l'activité, tel que renvoyé par le serveur
  /// (`cible: { kind, id }`).
  final String? cibleKind;
  final String? cibleId;

  const ActiviteEntree({
    required this.id,
    required this.type,
    required this.description,
    required this.auteur,
    required this.date,
    this.horsLigne = false,
    this.cibleKind,
    this.cibleId,
  });

  factory ActiviteEntree.fromJson(Map<String, dynamic> json) {
    final cible = json['cible'];
    return ActiviteEntree(
      id: json['id']?.toString() ?? '',
      type: json['type'] as String? ?? '',
      description: json['libelle'] as String? ?? '',
      auteur: json['utilisateur'] as String? ?? '',
      date: json['date']?.toString() ?? '',
      horsLigne: json['horsLigne'] == true,
      cibleKind: cible is Map ? cible['kind'] as String? : null,
      cibleId: cible is Map ? cible['id']?.toString() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'libelle': description,
        'utilisateur': auteur,
        'date': date,
        'horsLigne': horsLigne,
        if (cibleKind != null && cibleId != null)
          'cible': {'kind': cibleKind, 'id': cibleId},
      };

  /// Date de l'entrée, ou `null` si elle est illisible.
  ///
  /// Le serveur stocke la date en ISO la plupart du temps, mais son propre tri
  /// prévoit le cas d'un horodatage numérique (`typeof a.date === "number"`).
  /// Ne lire que l'ISO faisait disparaître ces entrées-là du fil des
  /// notifications, sans erreur ni trace.
  DateTime? get dateTime {
    if (date.isEmpty) return null;
    final millis = int.tryParse(date);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return DateTime.tryParse(date);
  }

  /// Date utilisée pour trier et comparer. Une entrée sans date lisible est
  /// rejetée tout au fond plutôt que placée au hasard.
  DateTime get dateTriable =>
      dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);

  FamilleActivite get famille =>
      _familleParType[type] ?? FamilleActivite.administration;

  String get titreNotification =>
      kTitreNotification[type] ?? 'Activité enregistrée';

  /// L'entrée a-t-elle été produite par [nomUtilisateur] ?
  ///
  /// Le serveur ne renvoie que le NOM de l'auteur, pas son identifiant : la
  /// comparaison se fait donc sur le nom, insensible à la casse et aux espaces.
  /// C'est ce qui évite de notifier quelqu'un de sa propre saisie — une
  /// notification qui répète ce qu'on vient de taper apprend à ignorer toutes
  /// les autres.
  bool estDe(String? nomUtilisateur) {
    if (nomUtilisateur == null) return false;
    final a = auteur.trim().toLowerCase();
    final b = nomUtilisateur.trim().toLowerCase();
    return a.isNotEmpty && a == b;
  }

  /// La page vers laquelle mène cette entrée, ou `null` si l'objet visé n'a pas
  /// d'écran dédié. Le journal reste alors la destination par défaut.
  String? get destination {
    final id = cibleId;
    if (id == null || id.isEmpty) return null;
    switch (cibleKind) {
      case 'article':
        return '/stock/article/$id';
      case 'client':
        return '/clients/$id';
      case 'facture':
        return '/factures/$id';
      case 'vente':
        return '/ventes';
      case 'depense':
        return '/depenses';
      case 'utilisateur':
      case 'appareil':
        return '/parametres';
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) => other is ActiviteEntree && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
