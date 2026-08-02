// lib/core/sauvegarde/sauvegarde.dart

import 'dart:convert';

// ─── Fichier de sauvegarde ────────────────────────────────────────────────────
// Transposition de `src/lib/sauvegarde.ts` de l'application web.
//
// Les deux applications lisent et écrivent le même format : une sauvegarde
// faite au comptoir doit pouvoir être restaurée au bureau, et l'inverse. Un
// test de chaque côté relit le fichier de l'autre pour s'en assurer.
//
// ── Pourquoi il n'y a pas d'empreinte cryptographique ──
//
// Un fichier tronqué — transfert interrompu, clé USB abîmée — fait déjà échouer
// l'analyse JSON : le cas est couvert. Une empreinte calculée en JavaScript
// puis vérifiée en Dart devrait sérialiser les nombres à l'identique, or `1.0`
// s'écrit « 1 » d'un côté et « 1.0 » de l'autre : l'application annoncerait
// « sauvegarde corrompue » sur un fichier sain, et plus personne n'oserait
// restaurer. Un garde-fou qui crie au loup est pire que pas de garde-fou.
//
// On vérifie donc ce qui est stable dans les deux langages : le résumé déclaré
// à l'écriture, confronté au contenu réellement présent. Ce sont des entiers.

/// Marque du fichier : reconnaître nos sauvegardes d'un autre JSON quelconque.
const String kFormatSauvegarde = 'eas-sarlu/sauvegarde';

/// Version du format de données, celle qu'émet le serveur.
const String kVersionFormat = '3.1';

/// Les collections attendues dans une sauvegarde complète.
const List<String> kCollectionsSauvegarde = [
  'articles',
  'ventes',
  'clients',
  'factures',
  'mouvements',
  'depenses',
];

/// Ce que contient la sauvegarde, en un coup d'œil.
class ResumeSauvegarde {
  final Map<String, int> parCollection;

  /// Nom de l'entreprise au moment de la sauvegarde, pour reconnaître le dépôt.
  final String entreprise;

  const ResumeSauvegarde({required this.parCollection, required this.entreprise});

  int operator [](String collection) => parCollection[collection] ?? 0;

  /// Nombre total d'enregistrements, toutes collections confondues.
  int get total => parCollection.values.fold(0, (s, n) => s + n);

  Map<String, dynamic> toJson() => {...parCollection, 'entreprise': entreprise};
}

int _compte(dynamic v) => v is List ? v.length : 0;

/// Compte ce que contient réellement une sauvegarde.
ResumeSauvegarde resumerSauvegarde(Map<String, dynamic> donnees) {
  final ent = donnees['entreprise'];
  return ResumeSauvegarde(
    parCollection: {
      for (final c in kCollectionsSauvegarde) c: _compte(donnees[c]),
    },
    entreprise:
        ent is Map && ent['nom'] is String ? ent['nom'] as String : '',
  );
}

/// Enveloppe les données du serveur dans le fichier qu'on écrit sur le disque.
Map<String, dynamic> construireEnveloppe(Map<String, dynamic> donnees) {
  final resume = resumerSauvegarde(donnees);
  return {
    'format': kFormatSauvegarde,
    'schemaVersion': '${donnees['schemaVersion'] ?? kVersionFormat}',
    'exportDate':
        '${donnees['exportDate'] ?? DateTime.now().toIso8601String()}',
    'resume': resume.toJson(),
    'donnees': donnees,
  };
}

String _p2(int n) => n.toString().padLeft(2, '0');

/// Nom de fichier proposé : reconnaissable, et triable par date.
String nomFichierSauvegarde([DateTime? maintenant]) {
  final d = maintenant ?? DateTime.now();
  return 'eas-sarlu-sauvegarde-${d.year}-${_p2(d.month)}-${_p2(d.day)}'
      '-${_p2(d.hour)}h${_p2(d.minute)}.json';
}

/// Le fichier n'est pas exploitable. Mieux vaut un refus net qu'une
/// restauration partielle.
class SauvegardeInvalide implements Exception {
  final String message;
  const SauvegardeInvalide(this.message);
  @override
  String toString() => message;
}

class SauvegardeLue {
  final Map<String, dynamic> donnees;

  /// Ce que le fichier contient réellement, recompté.
  final ResumeSauvegarde resume;
  final String exportDate;
  final String schemaVersion;

  /// Une sauvegarde d'avant l'enveloppe : acceptée, mais signalée.
  final bool ancienFormat;

  /// Ce qui mérite d'être dit avant de restaurer, sans pour autant refuser.
  final List<String> avertissements;

  const SauvegardeLue({
    required this.donnees,
    required this.resume,
    required this.exportDate,
    required this.schemaVersion,
    required this.ancienFormat,
    required this.avertissements,
  });
}

/// Lit un fichier de sauvegarde et dit ce qu'il contient.
///
/// Ne restaure rien : c'est ce qui permet de montrer à l'utilisateur ce qu'il
/// s'apprête à écraser AVANT qu'il ne le fasse. Restaurer en aveugle, c'est
/// découvrir qu'on a chargé la sauvegarde du mois dernier une fois les données
/// du mois en cours perdues.
SauvegardeLue lireSauvegarde(String texte) {
  dynamic brut;
  try {
    brut = jsonDecode(texte);
  } catch (_) {
    throw const SauvegardeInvalide(
        "Ce fichier n'est pas une sauvegarde lisible. S'il vient d'un transfert "
        'interrompu, refaites-le : un fichier coupé ne peut pas être réparé.');
  }

  if (brut is! Map) {
    throw const SauvegardeInvalide(
        'Ce fichier ne contient pas une sauvegarde.');
  }
  final objet = Map<String, dynamic>.from(brut);

  // Deux formes acceptées : l'enveloppe actuelle, et les sauvegardes d'avant
  // elle, qui portaient les collections à la racine. Les refuser reviendrait à
  // rendre inutilisables les fichiers déjà en circulation.
  final estEnveloppe =
      objet['format'] == kFormatSauvegarde && objet['donnees'] is Map;
  final donnees = Map<String, dynamic>.from(
      estEnveloppe ? objet['donnees'] as Map : objet);

  final presentes =
      kCollectionsSauvegarde.where((c) => donnees[c] is List).toList();
  if (presentes.isEmpty) {
    throw const SauvegardeInvalide(
        'Ce fichier ne contient aucune donnée du magasin : ni articles, ni '
        "ventes, ni clients. Ce n'est probablement pas une sauvegarde.");
  }

  final avertissements = <String>[];
  final resume = resumerSauvegarde(donnees);

  final manquantes =
      kCollectionsSauvegarde.where((c) => donnees[c] is! List).toList();
  if (manquantes.isNotEmpty) {
    avertissements.add(
        'Sauvegarde partielle : ${manquantes.join(', ')} absente(s) du fichier. '
        'Ces données seront vidées si vous restaurez.');
  }

  final version =
      '${objet['schemaVersion'] ?? donnees['schemaVersion'] ?? ''}';
  if (version.isNotEmpty && version.compareTo(kVersionFormat) > 0) {
    avertissements.add(
        "Cette sauvegarde vient d'une version plus récente de l'application "
        '(format $version, cette application lit $kVersionFormat). Des '
        "informations qu'elle contient pourraient être ignorées.");
  }

  // Le résumé déclaré à l'écriture, confronté au contenu réel. Ce sont des
  // entiers : la comparaison est fiable, quelle que soit l'application qui a
  // écrit le fichier. Un écart signale un fichier remanié à la main.
  final declare = estEnveloppe && objet['resume'] is Map
      ? Map<String, dynamic>.from(objet['resume'] as Map)
      : null;
  if (declare != null) {
    final ecarts = kCollectionsSauvegarde
        .where((c) => declare[c] is int && declare[c] != resume[c])
        .map((c) => '$c : ${declare[c]} annoncé, ${resume[c]} trouvé')
        .toList();
    if (ecarts.isNotEmpty) {
      avertissements.add(
          "Le contenu du fichier ne correspond pas à ce qu'il annonce "
          '(${ecarts.join(' ; ')}). Il a probablement été modifié après la '
          'sauvegarde.');
    }
  }

  return SauvegardeLue(
    donnees: donnees,
    resume: resume,
    exportDate: '${objet['exportDate'] ?? donnees['exportDate'] ?? ''}',
    schemaVersion: version.isEmpty ? kVersionFormat : version,
    ancienFormat: !estEnveloppe,
    avertissements: avertissements,
  );
}
