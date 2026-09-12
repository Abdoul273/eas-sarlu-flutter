// lib/app/format.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';

String fmtGNF(int montant) {
  final format = NumberFormat('#,##0', 'fr_FR');
  return '${format.format(montant)} GNF';
}

/// Lit un montant entier saisi par l'utilisateur, en nettoyant les espaces,
/// séparateurs et devises (ex: "100 000 GNF" -> 100000).
int parseMontantClean(String? input) {
  if (input == null) return 0;
  final clean = input.replaceAll(RegExp(r'[^\d]'), '');
  return int.tryParse(clean) ?? 0;
}

/// Lit un nombre décimal saisi par l'utilisateur, virgule ou point acceptés.
///
/// Le clavier numérique d'Android en français propose la VIRGULE : une
/// épaisseur tapée « 0,45 » passait par `double.tryParse` et devenait zéro,
/// une longueur « 6,5 » disparaissait. Rend `null` si rien de lisible.
double? parseDecimal(String? input) {
  if (input == null) return null;
  final clean = input.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (clean.isEmpty) return null;
  final v = double.tryParse(clean);
  return v == null || !v.isFinite ? null : v;
}

/// Un décimal tel qu'on le montre dans un champ ou une fiche : « 3 » et non
/// « 3.0 », « 0,45 » et non « 0.45 ».
String fmtDecimal(double v, {int decimales = 2}) {
  if (v == v.roundToDouble()) return v.round().toString();
  var t = v.toStringAsFixed(decimales);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t.replaceAll('.', ',');
}

String fmtDate(DateTime date) {
  return DateFormat.yMMMMd('fr_FR').format(date); // 29 juillet 2026
}

String fmtDateCourt(DateTime date) {
  return DateFormat('EEE d MMM y', 'fr_FR').format(date); // mer. 29 juil. 2026
}

String fmtNombre(num nombre) {
  return NumberFormat('#,##0', 'fr_FR').format(nombre.round());
}

/// Montant abrégé : « 12,5 Md GNF », « 340 M GNF », « 85 000 GNF ».
///
/// C'est le `gnf()` de l'application web. Réservé aux endroits où la place
/// manque ou bien où les deux applications doivent présenter le même ordre de
/// grandeur — le contexte envoyé à l'assistant, notamment. Partout où un
/// montant doit être lu au franc près, on emploie [fmtGNF], qui n'abrège pas :
/// une facture ne s'écrit pas « 2 M GNF ».
String gnfCompact(num n) {
  final a = n.abs();
  if (a >= 1000000000) {
    return '${NumberFormat('#,##0.0', 'fr_FR').format(n / 1000000000)} Md GNF';
  }
  if (a >= 1000000) {
    // Une décimale, comme pour les milliards. Sans elle, 1 650 000 GNF
    // s'affichait « 2 M GNF » : 350 000 francs évaporés dans un arrondi, sur un
    // chiffre que le gérant lit pour décider d'un achat. Le « .# » la fait
    // disparaître quand elle vaut zéro, si bien que 2 000 000 reste « 2 M ».
    return '${NumberFormat('#,##0.#', 'fr_FR').format(n / 1000000)} M GNF';
  }
  return '${fmtNombre(n)} GNF';
}

/// Séparateur de milliers à la française pour les documents PDF.
///
/// Emploie l'espace insécable (U+00A0) plutôt que l'espace fine insécable
/// retenue par `Intl` : cette dernière est absente du jeu de caractères WinAnsi
/// des polices PDF standard et sortait à une largeur erronée sur le document
/// imprimé. C'est la seule raison pour laquelle ce formateur existe à côté de
/// [fmtNombre] — à l'écran, `Intl` convient.
String numFRPdf(num n) {
  final entier = n.round();
  final signe = entier < 0 ? '-' : '';
  final chiffres = entier.abs().toString();
  final tampon = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(chiffres[i]);
  }
  return '$signe$tampon';
}

/// Date au format numérique jj-mm-aaaa, celui de la facture papier du magasin.
/// Une date illisible rend une chaîne vide plutôt qu'un « null » imprimé.
String fmtDateNum(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return '';
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}-${p(d.month)}-${d.year}';
}

/// Assemble les morceaux non vides d'une adresse ou d'un bloc de coordonnées.
///
/// Évite les « Conakry ·  · » disgracieux quand un champ n'est pas renseigné :
/// un magasin sans site web ne doit pas imprimer un séparateur orphelin.
String joindreNonVides(List<String?> parties, [String sep = ' · ']) =>
    parties.map((p) => (p ?? '').trim()).where((p) => p.isNotEmpty).join(sep);

// ─── Montant en toutes lettres ────────────────────────────────────────────────
// La facture papier porte la mention « Le montant en mots : … » ; c'est elle qui
// fait foi en cas de contestation sur les chiffres. Écriture française standard
// (« quatre-vingts », « cent » accordé, « mille » invariable). Transposition de
// `montantEnLettres` (src/lib/format.ts) de l'application web.

const _unites = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit',
  'neuf', 'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize',
  'dix-sept', 'dix-huit', 'dix-neuf',
];

const _dizaines = [
  '', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'soixante',
  'quatre-vingt', 'quatre-vingt',
];

String _sousCent(int n) {
  if (n < 20) return _unites[n];
  final d = n ~/ 10, u = n % 10;
  // 70 et 90 se disent « soixante-dix » et « quatre-vingt-dix » : on repart de
  // la dizaine inférieure et on compte jusqu'à 19. Et 71 fait « soixante et
  // onze », comme 21 fait « vingt et un » — 91 seul reste sans « et ».
  if (d == 7 && u == 1) return 'soixante et onze';
  if (d == 7 || d == 9) return '${_dizaines[d]}-${_unites[10 + u]}';
  if (u == 0) return d == 8 ? 'quatre-vingts' : _dizaines[d];
  if (u == 1 && d != 8) return '${_dizaines[d]} et un';
  return '${_dizaines[d]}-${_unites[u]}';
}

/// [devantMille] : « cent » ne prend pas de s quand « mille » le suit
/// (« trois cent mille »), alors qu'il le prend devant « millions » ou en fin
/// de nombre, qui sont des noms (« deux cents millions », « deux cents »).
String _sousMille(int n, {bool devantMille = false}) {
  final c = n ~/ 100, r = n % 100;
  if (c == 0) return _sousCent(r);
  if (r == 0) {
    if (c == 1) return 'cent';
    return devantMille ? '${_unites[c]} cent' : '${_unites[c]} cents';
  }
  final tete = c == 1 ? 'cent' : '${_unites[c]} cent';
  return '$tete ${_sousCent(r)}';
}

/// Le montant écrit en toutes lettres, sans la devise.
///
/// Arrondi à l'unité : la facture du magasin ne porte pas de centimes, et
/// « mille virgule quatre » ne s'écrit pas sur une pièce comptable.
String montantEnLettres(num montant) {
  var v = montant.round().abs();
  if (v == 0) return 'zéro';
  final n = montant;
  const tranches = [
    [1000000000, 'milliard', 'milliards'],
    [1000000, 'million', 'millions'],
    [1000, 'mille', 'mille'],
  ];
  final morceaux = <String>[];
  for (final t in tranches) {
    final poids = t[0] as int;
    final q = v ~/ poids;
    if (q == 0) continue;
    v -= q * poids;
    // « mille » ne prend jamais de s et ne se dit pas « un mille ».
    if (poids == 1000) {
      // « quatre-vingt mille » : comme « cent », « vingt » reste invariable
      // devant « mille ».
      final tete = _sousMille(q, devantMille: true)
          .replaceFirst(RegExp(r'quatre-vingts$'), 'quatre-vingt');
      morceaux.add(q == 1 ? 'mille' : '$tete mille');
    } else {
      morceaux.add('${_sousMille(q)} ${q == 1 ? t[1] : t[2]}');
    }
  }
  if (v > 0) morceaux.add(_sousMille(v));
  return (n < 0 ? 'moins ' : '') + morceaux.join(' ');
}

// --- Dates venant du serveur (chaînes ISO 8601) ---

/// Format Date & Heure exacte : « jeu. 30/07/26 8:15 »
String fmtDateHeureExacte(DateTime date) {
  return DateFormat('EEE dd/MM/yy H:mm', 'fr_FR').format(date);
}

/// Date longue depuis une chaîne ISO. « 29 juillet 2026 »
String fmtDateIso(String? iso, {String siInvalide = '—'}) {
  final date = iso == null ? null : DateTime.tryParse(iso);
  return date == null ? siInvalide : fmtDate(date);
}

/// Date courte depuis une chaîne ISO. « mer. 29 juil. 2026 »
String fmtDateCourtIso(String? iso, {String siInvalide = '—'}) {
  final date = iso == null ? null : DateTime.tryParse(iso);
  return date == null ? siInvalide : fmtDateCourt(date);
}

/// Date & heure exacte depuis une chaîne ISO. « jeu. 30/07/26 8:15 »
String fmtDateHeureExacteIso(String? iso, {String siInvalide = '—'}) {
  final date = iso == null ? null : DateTime.tryParse(iso);
  return date == null ? siInvalide : fmtDateHeureExacte(date);
}

/// Heure seule depuis une chaîne ISO. « 14:05 »
String fmtHeureIso(String? iso, {String siInvalide = '—'}) {
  final date = iso == null ? null : DateTime.tryParse(iso);
  return date == null ? siInvalide : DateFormat('HH:mm').format(date);
}

/// Décode de manière sécurisée une chaîne base64 (avec ou sans préfixe `data:image/...;base64,`).
/// Renvoie `null` si la chaîne est nulle, vide ou invalide au lieu d'interrompre l'exécution.
Uint8List? bytesFromBase64(String? input) {
  if (input == null) return null;
  var data = input.trim();
  if (data.isEmpty) return null;

  final comma = data.indexOf(',');
  if (data.startsWith('data:') && comma != -1) {
    data = data.substring(comma + 1);
  }
  data = data.replaceAll(RegExp(r'\s'), '');
  if (data.isEmpty) return null;

  try {
    final bytes = base64Decode(data);
    if (bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}
