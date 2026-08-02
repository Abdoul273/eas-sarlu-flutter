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
    return '${NumberFormat('#,##0', 'fr_FR').format(n / 1000000)} M GNF';
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
  // la dizaine inférieure et on compte jusqu'à 19.
  if (d == 7 || d == 9) return '${_dizaines[d]}-${_unites[10 + u]}';
  if (u == 0) return d == 8 ? 'quatre-vingts' : _dizaines[d];
  if (u == 1 && d != 8) return '${_dizaines[d]} et un';
  return '${_dizaines[d]}-${_unites[u]}';
}

String _sousMille(int n) {
  final c = n ~/ 100, r = n % 100;
  if (c == 0) return _sousCent(r);
  if (r == 0) return c == 1 ? 'cent' : '${_unites[c]} cents';
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
      morceaux.add(q == 1 ? 'mille' : '${_sousMille(q)} mille');
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
