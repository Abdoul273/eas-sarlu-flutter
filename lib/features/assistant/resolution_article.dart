import 'dart:math' as math;

import '../../core/models/models.dart';

// ─── Reconnaître un article dans une phrase ───────────────────────────────────
//
// « Ajoute 10 barres de cornière 30 à mon stock. »
//
// Jusqu'ici l'assistant tranchait ça avec un `contains` : le premier article
// dont le nom contenait le texte gagnait, et si aucun ne le contenait, il
// proposait d'en créer un. Deux façons de se tromper, et les deux coûtent cher
// au magasin :
//
//   — le doublon. « cornière 30 » ne se retrouve pas tel quel dans « Cornière L
//     30×30×3 mm (6 m) » : aucune correspondance, donc création d'une deuxième
//     référence de cornière 30. Le stock se scinde en deux, la valorisation
//     ment, et les deux lignes divergent lentement.
//   — la confusion. Une cornière 30 NOIRE et une cornière 30 GALVA sont deux
//     marchandises, deux prix, deux fournisseurs. Un `contains` les confond ;
//     l'entrée de stock atterrit sur la mauvaise, et personne ne le voit.
//
// Ce fichier remplace la ressemblance de chaînes par une lecture du métier. Un
// nom d'article de quincaillerie métallique n'est pas du texte libre : c'est une
// famille (cornière, tube carré, IPN), des sections (30×30×3), une épaisseur
// (e=2 mm), une longueur (6 m) et une finition (noir, galva). Chacun de ces
// attributs est extrait des deux côtés — de la phrase du commerçant et de la
// fiche article — puis comparé.
//
// La distinction qui commande tout le reste :
//
//   · un attribut ABSENT de la fiche n'est pas une contradiction. Le catalogue
//     ne dit pas « noire » sur ses cornières parce que le noir y va de soi. On
//     ne rejette pas l'article : on note l'imprécision, et l'assistant la pose
//     en question au lieu de deviner ;
//   · un attribut DIFFÉRENT en est une. Galva contre noir, 2 mm contre 3 mm,
//     6 m contre 12 m : ce sont des articles distincts, et le seul geste correct
//     est de le dire — puis de proposer, éventuellement, la création de la
//     variante manquante.
//
// Rien ici ne décide seul : la fonction rend un verdict et de quoi le raconter.
// C'est `ai_outils.dart` qui le donne à lire au modèle, et
// `action_executeur.dart` qui refuse d'écrire quand le verdict dit d'attendre.

/// Ce qu'une désignation d'article dit, une fois décomposée.
class SpecArticle {
  /// « Cornière », « Tube carré », « IPN »… telle que le catalogue les nomme.
  final String? famille;

  /// Les sections lues d'un groupe « 30×30×3 », dans l'ordre.
  final List<double> dimensions;

  /// Millimètres. Pour un profilé à trois cotes, c'est la troisième.
  final double? epaisseur;

  /// Mètres. Une barre de 6 m et une de 12 m ne sont pas le même article.
  final double? longueur;

  /// Le Ø d'un tube rond ou d'un fer à béton.
  final double? diametre;

  /// « noir », « galvanisé », « inox », « prélaqué », « ondulé ».
  final String? finition;

  /// Les nombres cités sans unité ni groupe — « cornière 30 ». Ils désignent
  /// presque toujours une cote, mais on ne sait pas laquelle.
  final List<double> nombresLibres;

  const SpecArticle({
    this.famille,
    this.dimensions = const [],
    this.epaisseur,
    this.longueur,
    this.diametre,
    this.finition,
    this.nombresLibres = const [],
  });

  bool get estVide =>
      famille == null &&
      dimensions.isEmpty &&
      epaisseur == null &&
      longueur == null &&
      diametre == null &&
      finition == null &&
      nombresLibres.isEmpty;

  /// Ce qui a été compris, dit en français — pour que le commerçant puisse
  /// corriger l'assistant quand celui-ci a mal lu sa phrase.
  String get libelle {
    final bouts = <String>[
      if (famille != null) famille!,
      if (dimensions.isNotEmpty)
        dimensions.map(_nombre).join('×')
      else if (nombresLibres.isNotEmpty)
        nombresLibres.map(_nombre).join(', '),
      if (diametre != null) 'Ø${_nombre(diametre!)}',
      if (epaisseur != null && dimensions.length != 3)
        'ép. ${_nombre(epaisseur!)} mm',
      if (longueur != null) '${_nombre(longueur!)} m',
      if (finition != null) finition!,
    ];
    return bouts.isEmpty ? '—' : bouts.join(' ');
  }
}

/// Un article confronté à une demande.
class Correspondance {
  final Article article;

  /// 0 à 1. Au-delà de [_seuilRetenu] l'article est un candidat sérieux.
  final double score;

  /// Ce qui concorde explicitement : « épaisseur 3 mm », « longueur 6 m ».
  final List<String> accords;

  /// Ce qui se contredit. Un seul suffit à faire de cet article un AUTRE
  /// article — jamais celui que l'on cherche.
  final List<String> conflits;

  /// Ce que la demande précise et que la fiche tait. Ni accord ni contradiction :
  /// une question à poser.
  final List<String> imprecisions;

  const Correspondance({
    required this.article,
    required this.score,
    this.accords = const [],
    this.conflits = const [],
    this.imprecisions = const [],
  });

  bool get compatible => conflits.isEmpty;
}

/// Ce que la résolution conclut.
enum VerdictArticle {
  /// Un article, et un seul, correspond. On peut proposer un mouvement de stock.
  exact,

  /// Plusieurs conviennent également. Il faut demander lequel — jamais choisir.
  ambigu,

  /// La famille existe au catalogue, mais dans une autre déclinaison :
  /// galva au lieu de noir, 2 mm au lieu de 3. C'est un article à créer, pas un
  /// stock à mouvementer.
  variante,

  /// Rien d'approchant. Création franche, après confirmation.
  aucun,
}

class ResolutionArticle {
  final VerdictArticle verdict;

  /// Le terme d'origine, tel que l'assistant l'a transmis.
  final String terme;

  /// Ce qui a été compris de ce terme.
  final SpecArticle demande;

  /// L'article retenu, quand le verdict est [VerdictArticle.exact].
  final Article? article;

  /// Les articles entre lesquels il faut trancher (verdict ambigu), ou les
  /// déclinaisons voisines (verdict variante).
  final List<Correspondance> candidats;

  const ResolutionArticle({
    required this.verdict,
    required this.terme,
    required this.demande,
    this.article,
    this.candidats = const [],
  });

  /// Les précisions de la demande que la fiche retenue ne confirme pas.
  List<String> get imprecisions => candidats.isEmpty
      ? const []
      : candidats.first.article.id == article?.id
          ? candidats.first.imprecisions
          : const [];
}

// ─── Normalisation ────────────────────────────────────────────────────────────

const Map<String, String> _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
};

/// Ramène un texte à une forme comparable : sans accents, sans typographie, avec
/// un seul signe de multiplication et un seul séparateur décimal.
///
/// Le magasin écrit « 30×30 », le modèle « 30x30 », le commerçant pressé
/// « 30*30 ». Trois façons d'écrire la même cornière ; une seule doit survivre
/// ici, sans quoi la comparaison échoue sur une question de clavier.
String normaliser(String texte) {
  var s = texte.toLowerCase();
  final b = StringBuffer();
  for (final c in s.split('')) {
    b.write(_accents[c] ?? c);
  }
  s = b.toString();
  // Le Ø devient un mot : sans cela il disparaît avec la ponctuation, et
  // « Ø21 » ne se distingue plus de « 21 ».
  s = s.replaceAll(RegExp(r'[øØ]'), ' diam ');
  s = s.replaceAll(RegExp(r'\b(diametre|diam\.|ø)\b'), ' diam ');
  // La virgule décimale d'abord : « 1,5 mm » doit rester un nombre.
  s = s.replaceAllMapped(RegExp(r'(\d)\s*,\s*(\d)'), (m) => '${m[1]}.${m[2]}');
  s = s.replaceAll(RegExp(r'[×*]'), 'x');
  // Tout le reste de la ponctuation devient de l'espace. On garde « = » parce
  // que « e=2 » est la façon dont le catalogue note une épaisseur.
  s = s.replaceAll(RegExp(r'[^a-z0-9.=x ]'), ' ');
  // Un point qui ne sépare pas deux chiffres est une abréviation, pas un décimal.
  s = s.replaceAllMapped(
      RegExp(r'\.(?!\d)|(?<!\d)\.'), (_) => ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ─── Les familles du catalogue ────────────────────────────────────────────────
//
// L'ordre compte : « tube rectangulaire » doit être reconnu avant « tube », et
// « tôle galvanisée » avant « tôle ». Le premier motif qui accroche gagne.

const List<(String, String)> _familles = [
  ('Tube rectangulaire', r'tube\s*rect|rectangulaire|\btre\b'),
  ('Tube carré', r'tube\s*carre|\btc\b'),
  ('Tube rond', r'tube\s*rond|\btr\b'),
  ('Fer H (HEA/HEB)', r'\bhea\b|\bheb\b|fer\s*h\b|poutrelle\s*h\b'),
  ('IPN', r'\bipn\b'),
  ('UPN', r'\bupn\b'),
  ('Cornière', r'corniere|\bcorniere\b|\bangle\b|\bl\s*\d'),
  ('Fer plat', r'fer\s*plat|\bplat\b|meplat'),
  ('Fer à béton', r'fer\s*a?\s*beton|\bha\b|\btor\b|beton\s*ha'),
  ('Tôle ondulée', r'tole\s*ondulee|ondulee?\b|\bbac\b'),
  ('Tôle galvanisée', r'tole\s*galva\w*'),
  ('Tôle noire', r'tole\s*noire?'),
];

/// La finition, c'est-à-dire le traitement de surface. C'est l'attribut que le
/// commerçant cite le plus souvent et que les noms du catalogue portent le
/// moins : d'où l'importance de ne jamais le deviner.
const List<(String, String)> _finitions = [
  ('galvanisé', r'galva\w*|zingu\w*|\bgi\b'),
  ('inox', r'\binox\b|inoxydable'),
  ('prélaqué', r'prelaqu\w*|laqu\w*|peint\w*|\bral\s*\d+'),
  ('ondulé', r'ondul\w*|\bbac\s*acier\b'),
  ('noir', r'\bnoire?\b|\bbrut\w*\b'),
];

/// Les finitions que le catalogue peut taire sans mentir. L'acier noir est
/// l'état par défaut du dépôt : personne n'écrit « cornière noire », on écrit
/// « cornière ». Toutes les autres se déclarent — un article inox qui ne le
/// dirait pas n'existe pas.
const Set<String> _finitionsImplicites = {'noir'};

const Set<String> _motsVides = {
  'de', 'du', 'des', 'la', 'le', 'les', 'un', 'une', 'et', 'ou', 'en', 'au',
  'aux', 'pour', 'avec', 'dans', 'sur', 'mon', 'ma', 'mes', 'notre', 'nos',
  'ce', 'cet', 'cette', 'stock', 'ajoute', 'ajouter', 'ajout', 'entree',
  'sortie', 'article', 'articles', 'ref', 'reference', 'mm', 'cm', 'metre',
  'metres', 'unite', 'unites', 'piece', 'pieces', 'barre', 'barres', 'plaque',
  'plaques', 'sac', 'sacs', 'qte', 'quantite', 'svp', 'stp', 'merci',
};

double? _premier(RegExpMatch? m, [int groupe = 1]) =>
    m == null ? null : double.tryParse(m.group(groupe) ?? '');

String _nombre(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// Décompose une désignation — celle du commerçant comme celle du catalogue.
///
/// Quand un [article] est fourni, ses champs structurés (`epaisseur`,
/// `longueur`, `categorie`) l'emportent sur ce que le nom laisse deviner : ils
/// ont été saisis dans une fiche, pas déduits d'une chaîne.
SpecArticle extraireSpec(String texte, {Article? article}) {
  final n = normaliser(
    [
      texte,
      if (article != null) article.categorie,
      if (article != null) article.description,
    ].where((x) => x.trim().isNotEmpty).join(' '),
  );

  String? famille;
  for (final (nom, motif) in _familles) {
    if (RegExp(motif).hasMatch(n)) {
      famille = nom;
      break;
    }
  }

  String? finition;
  for (final (nom, motif) in _finitions) {
    if (RegExp(motif).hasMatch(n)) {
      finition = nom;
      break;
    }
  }

  // Les groupes de cotes : « 30x30x3 », « 2000x1000 ».
  final dims = <double>[];
  final consommes = <double>{};
  for (final m in RegExp(
          r'(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)(?:\s*x\s*(\d+(?:\.\d+)?))?')
      .allMatches(n)) {
    for (var g = 1; g <= 3; g++) {
      final v = _premier(m, g);
      if (v != null) {
        dims.add(v);
        consommes.add(v);
      }
    }
  }

  final diametre =
      _premier(RegExp(r'\bdiam\s*(\d+(?:\.\d+)?)').firstMatch(n));
  if (diametre != null) consommes.add(diametre);

  // « e=2 », « ep 3 », « épaisseur 1.5 ».
  var epaisseur =
      _premier(RegExp(r'\be\s*=\s*(\d+(?:\.\d+)?)').firstMatch(n)) ??
          _premier(RegExp(r'\bep(?:aisseur)?\s*=?\s*(\d+(?:\.\d+)?)')
              .firstMatch(n));
  // Un nombre suivi de « mm » et qui n'appartient à aucun groupe de cotes est
  // une épaisseur : c'est ainsi que se nomment les tôles (« Tôle noire 2 mm »).
  if (epaisseur == null) {
    for (final m in RegExp(r'(\d+(?:\.\d+)?)\s*mm').allMatches(n)) {
      final v = _premier(m);
      if (v != null && !consommes.contains(v)) {
        epaisseur = v;
        break;
      }
    }
  }
  // Sur un profilé à trois cotes, la troisième EST l'épaisseur.
  if (epaisseur == null && dims.length >= 3) epaisseur = dims[2];
  if (epaisseur != null) consommes.add(epaisseur);

  // « (6 m) », « 12 m » — le « m » ne doit pas être celui de « mm ».
  final longueur =
      _premier(RegExp(r'\b(\d+(?:\.\d+)?)\s*m(?![a-z0-9])').firstMatch(n));
  if (longueur != null) consommes.add(longueur);

  // Ce qui reste : « cornière 30 ». Une cote, sans qu'on sache laquelle.
  final libres = <double>[];
  for (final m in RegExp(r'(?<![\d.x])(\d+(?:\.\d+)?)(?![\d.]*\s*x)')
      .allMatches(n)) {
    final v = _premier(m);
    if (v == null || consommes.contains(v) || libres.contains(v)) continue;
    libres.add(v);
  }

  // La fiche fait foi là où elle est renseignée : ces champs ont été saisis
  // dans un formulaire, alors que le reste est déduit d'une chaîne de texte.
  final fiche = article;
  return SpecArticle(
    famille: famille ?? (fiche == null ? null : _familleDe(fiche.categorie)),
    dimensions: dims,
    epaisseur: (fiche != null && fiche.epaisseur > 0) ? fiche.epaisseur : epaisseur,
    longueur: (fiche?.longueur != null && fiche!.longueur! > 0)
        ? fiche.longueur
        : longueur,
    diametre: diametre,
    finition: finition,
    nombresLibres: libres,
  );
}

String? _familleDe(String categorie) {
  final n = normaliser(categorie);
  if (n.isEmpty) return null;
  for (final (nom, motif) in _familles) {
    if (RegExp(motif).hasMatch(n)) return nom;
  }
  return categorie.trim().isEmpty ? null : categorie.trim();
}

// ─── Comparaison ──────────────────────────────────────────────────────────────

/// En dessous, l'article n'est même pas montré : le citer ferait du bruit dans
/// une question qui doit rester lisible.
const double _seuilRetenu = 0.34;

/// Au-dessus, et sans rival proche, on tient l'article sans rien demander.
const double _seuilCertitude = 0.62;

/// L'écart qui sépare une évidence d'une hésitation. En dessous, deux articles
/// se valent, et trancher au hasard reviendrait à mouvementer le mauvais stock.
const double _ecartDecisif = 0.14;

bool _proche(double a, double b) => (a - b).abs() < 0.001;

/// Confronte une demande à un article, attribut par attribut.
Correspondance comparer(Article article, String terme, {SpecArticle? demande}) {
  final spec = demande ?? extraireSpec(terme);
  final t = normaliser(terme);

  // Une référence ou un identifiant cité au mot près ne se discute pas : c'est
  // la façon la plus sûre de désigner un article, et elle doit court-circuiter
  // toute la mécanique de ressemblance.
  if (t.isNotEmpty &&
      (normaliser(article.ref) == t ||
          article.id.toLowerCase() == terme.toLowerCase().trim() ||
          normaliser(article.nom) == t)) {
    return Correspondance(article: article, score: 1, accords: const ['référence exacte']);
  }

  final specArticle = extraireSpec(article.nom, article: article);
  final haystack = normaliser([
    article.nom,
    article.ref,
    article.categorie,
    article.description,
    article.fournisseur,
    article.provenance,
  ].join(' '));

  final accords = <String>[];
  final conflits = <String>[];
  final imprecisions = <String>[];

  // 1. Les mots. La base du score : ce que la phrase nomme se retrouve-t-il ?
  final mots = t
      .split(' ')
      .where((m) => m.length >= 3 && !_motsVides.contains(m) && !RegExp(r'^\d').hasMatch(m))
      .toSet();
  final trouves = mots.where((m) => haystack.contains(m)).length;
  var score = mots.isEmpty ? 0.30 : 0.45 * (trouves / mots.length);

  // 2. La famille. Deux familles nommées et différentes : ce n'est pas la même
  // marchandise, quoi que disent les chiffres.
  if (spec.famille != null && specArticle.famille != null) {
    if (spec.famille == specArticle.famille) {
      score += 0.22;
      accords.add(spec.famille!);
    } else {
      conflits.add('famille ${specArticle.famille} ≠ ${spec.famille}');
    }
  }

  // 3. Les attributs chiffrés et la finition.
  void confronter(String nom, double? voulu, double? offert, String unite) {
    if (voulu == null) return;
    if (offert == null) {
      imprecisions.add('$nom non renseignée sur la fiche');
      return;
    }
    if (_proche(voulu, offert)) {
      score += 0.09;
      accords.add('$nom ${_nombre(offert)}$unite');
    } else {
      conflits.add(
          '$nom ${_nombre(offert)}$unite ≠ ${_nombre(voulu)}$unite');
    }
  }

  confronter('épaisseur', spec.epaisseur, specArticle.epaisseur, ' mm');
  confronter('longueur', spec.longueur, specArticle.longueur, ' m');
  confronter('diamètre', spec.diametre, specArticle.diametre, '');

  if (spec.finition != null) {
    if (specArticle.finition == spec.finition) {
      score += 0.12;
      accords.add(spec.finition!);
    } else if (specArticle.finition != null) {
      conflits.add('finition ${specArticle.finition} ≠ ${spec.finition}');
    } else if (_finitionsImplicites.contains(spec.finition)) {
      // Le catalogue n'écrit pas « noire » sur ses cornières : le noir y va de
      // soi. Silence n'est pas contradiction — mais ne vaut pas confirmation,
      // et l'assistant devra dire l'hypothèse qu'il fait.
      imprecisions
          .add('finition « ${spec.finition} » non précisée sur la fiche');
    } else {
      // L'inox, la galva, le prélaqué ne se taisent pas : une fiche qui n'en
      // dit rien décrit autre chose. C'est ce silence-là qui faisait passer une
      // entrée de cornière inox sur la cornière ordinaire.
      conflits.add('cet article n\'est pas annoncé ${spec.finition}');
    }
  }

  // 4. Les cotes. Toutes celles qui sont demandées doivent se retrouver ;
  // une seule manquante suffit à changer d'article.
  final cotesArticle = <double>{
    ...specArticle.dimensions,
    ...specArticle.nombresLibres,
    if (specArticle.epaisseur != null) specArticle.epaisseur!,
    if (specArticle.diametre != null) specArticle.diametre!,
  };
  final cotesVoulues = <double>{...spec.dimensions, ...spec.nombresLibres};
  if (cotesVoulues.isNotEmpty) {
    final manquantes =
        cotesVoulues.where((v) => !cotesArticle.any((c) => _proche(c, v))).toList();
    if (manquantes.isEmpty) {
      score += 0.20;
      accords.add('cotes ${cotesVoulues.map(_nombre).join('×')}');
    } else {
      conflits.add(
          'cote${manquantes.length > 1 ? 's' : ''} ${manquantes.map(_nombre).join(', ')} absente'
          '${manquantes.length > 1 ? 's' : ''} de cet article');
    }
  }

  // Un conflit ne disqualifie pas l'article de l'affichage — c'est justement la
  // variante voisine qu'il faut montrer au commerçant — mais il l'écarte de tout
  // choix automatique.
  if (conflits.isNotEmpty) score *= 0.4;

  return Correspondance(
    article: article,
    score: math.min(1, score),
    accords: accords,
    conflits: conflits,
    imprecisions: imprecisions,
  );
}

/// Classe tout le catalogue face à une demande, du plus probable au moins.
List<Correspondance> classer(List<Article> articles, String terme) {
  final spec = extraireSpec(terme);
  final l = articles
      .map((a) => comparer(a, terme, demande: spec))
      .where((c) => c.score >= _seuilRetenu * 0.5)
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return l;
}

/// Le point d'entrée : que faire de « cornière 30 » ?
ResolutionArticle resoudreArticle(List<Article> articles, String terme) {
  final t = terme.trim();
  final spec = extraireSpec(t);
  if (t.isEmpty) {
    return ResolutionArticle(
        verdict: VerdictArticle.aucun, terme: t, demande: spec);
  }

  final tous = classer(articles, t);
  final compatibles =
      tous.where((c) => c.compatible && c.score >= _seuilRetenu).toList();
  final voisins = tous
      .where((c) => !c.compatible && c.score >= _seuilRetenu * 0.5)
      .take(6)
      .toList();

  if (compatibles.isEmpty) {
    // Rien qui convienne, mais peut-être la même chose dans une autre
    // déclinaison — c'est le cas « je n'ai que la galva, tu me demandes la
    // noire ». Le distinguer de « je n'ai rien » change la réponse du tout au
    // tout : dans un cas on crée une variante d'un article connu, dans l'autre
    // on ouvre une famille nouvelle.
    return ResolutionArticle(
      verdict: voisins.isEmpty ? VerdictArticle.aucun : VerdictArticle.variante,
      terme: t,
      demande: spec,
      candidats: voisins,
    );
  }

  final premier = compatibles.first;
  final second = compatibles.length > 1 ? compatibles[1] : null;
  final decisif = second == null ||
      (premier.score - second.score) >= _ecartDecisif;

  if (decisif && premier.score >= _seuilCertitude) {
    return ResolutionArticle(
      verdict: VerdictArticle.exact,
      terme: t,
      demande: spec,
      article: premier.article,
      candidats: [premier, ...voisins.take(3)],
    );
  }

  // Un seul candidat mais un score tiède : on le nomme et on fait confirmer,
  // plutôt que de mouvementer un stock sur une intuition.
  return ResolutionArticle(
    verdict: VerdictArticle.ambigu,
    terme: t,
    demande: spec,
    candidats: [...compatibles.take(6), ...voisins.take(3)],
  );
}

/// Les articles que la création de [nom] risque de dupliquer.
///
/// Plus permissif que [resoudreArticle] : ici on cherche le doute, pas la
/// certitude. Mieux vaut montrer une référence voisine pour rien que laisser
/// naître un deuxième « Cornière 30 » à côté du premier.
List<Correspondance> articlesSemblables(List<Article> articles, String nom) =>
    classer(articles, nom).where((c) => c.score >= _seuilRetenu).take(6).toList();

// ─── Ce que le modèle en lit ──────────────────────────────────────────────────

/// Met le verdict en français, avec la consigne qui va avec.
///
/// Le texte s'adresse au modèle et lui dit quoi faire, parce qu'une donnée
/// remise sans consigne se fait ignorer : on a vu l'assistant lister trois
/// candidats puis en choisir un tout seul dans la phrase suivante.
String expliquerResolution(ResolutionArticle r, {bool voitPrixAchat = true}) {
  String ligne(Correspondance c) {
    final a = c.article;
    final details = <String>[
      'stock ${_nombre(a.stock.toDouble())} ${a.unite}',
      if (voitPrixAchat) 'achat ${a.prixAchat} GNF',
      'vente ${a.prixVente} GNF',
      if (c.accords.isNotEmpty) 'concorde : ${c.accords.join(', ')}',
      if (c.conflits.isNotEmpty) 'DIFFÈRE : ${c.conflits.join(' ; ')}',
      if (c.imprecisions.isNotEmpty) 'à vérifier : ${c.imprecisions.join(' ; ')}',
    ];
    return '- ${a.nom} [${a.ref}] — id ${a.id} | ${details.join(' | ')}';
  }

  final entete = 'RÉSOLUTION D\'ARTICLE — demande « ${r.terme} » '
      '(comprise comme : ${r.demande.libelle})';

  switch (r.verdict) {
    case VerdictArticle.exact:
      final c = r.candidats.first;
      final sansImprecision = c.imprecisions.isEmpty;
      return [
        entete,
        '',
        'TROUVÉ, un seul article correspond :',
        ligne(c),
        '',
        sansImprecision
            ? 'Cet article EXISTE DÉJÀ. N\'en crée surtout pas un deuxième : '
                'propose addStock ou removeStock avec "articleId":"${c.article.id}".'
            : 'Cet article EXISTE DÉJÀ, mais sa fiche ne confirme pas tout ce que '
                'la demande précise (${c.imprecisions.join(' ; ')}). '
                'Nomme l\'article dans ta réponse, dis l\'hypothèse que tu fais, '
                'et propose addStock sur "articleId":"${c.article.id}". '
                'Si le commerçant voulait une AUTRE déclinaison, il te le dira — '
                'ce sera alors un createArticle.',
        if (r.candidats.length > 1) ...[
          '',
          'Déclinaisons voisines, à ne pas confondre :',
          ...r.candidats.skip(1).map(ligne),
        ],
      ].join('\n');

    case VerdictArticle.ambigu:
      return [
        entete,
        '',
        '${r.candidats.where((c) => c.compatible).length} articles conviennent également. '
            'NE CHOISIS PAS À SA PLACE.',
        ...r.candidats.map(ligne),
        '',
        'Pose UNE question courte au commerçant pour trancher, en citant ce qui '
            'les distingue (épaisseur, longueur, finition, section) — pas leurs '
            'identifiants. N\'émets AUCUNE action tant qu\'il n\'a pas répondu, et '
            'ne crée pas d\'article : ils existent déjà.',
      ].join('\n');

    case VerdictArticle.variante:
      return [
        entete,
        '',
        'AUCUN article ne correspond exactement, mais le catalogue contient des '
            'déclinaisons proches, qui en DIFFÈRENT sur un point :',
        ...r.candidats.map(ligne),
        '',
        'C\'est probablement une variante à créer (finition, épaisseur ou longueur '
            'différente = article différent : une cornière galva n\'est pas une '
            'cornière noire). Explique au commerçant ce que tu as trouvé et ce qui '
            'diffère, puis DEMANDE-LUI s\'il veut bien créer une nouvelle référence — '
            'ou s\'il parlait en fait de l\'une de celles-ci. '
            'S\'il confirme la création, propose createArticle avec '
            '"confirmerNouveau":"oui", en reprenant catégorie, unité et seuil de '
            'l\'article voisin, et en LAISSANT VIDES les prix : il les donnera.',
      ].join('\n');

    case VerdictArticle.aucun:
      return [
        entete,
        '',
        'Aucun article du catalogue n\'approche cette désignation.',
        '',
        'Avant de proposer createArticle : redis au commerçant, en une phrase, que '
            'cette référence n\'existe pas encore, et demande-lui confirmation ainsi '
            'que ce qui manque (prix de vente, unité, catégorie). Une fois qu\'il a '
            'confirmé, propose createArticle avec "confirmerNouveau":"oui". '
            'N\'invente aucun prix.',
      ].join('\n');
  }
}
