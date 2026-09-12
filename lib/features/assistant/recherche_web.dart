import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Recherche web via SerpAPI ────────────────────────────────────────────────
// L'assistant ne connaît du monde que ce qu'il a appris pendant son
// entraînement : sur le prix du ciment ou le taux du dollar, il répond avec des
// chiffres périmés sans le savoir. C'est exactement ce qu'il ne faut pas sur des
// nombres qui servent à acheter. On lui donne donc de quoi aller vérifier.
//
// L'application web passe par son serveur (« /api/search ») parce qu'un
// navigateur ne peut pas appeler SerpAPI : pas d'en-têtes CORS, et une clé
// exposée à qui ouvre les outils de développement. Une application Android n'a
// ni l'une ni l'autre de ces contraintes : elle appelle SerpAPI directement, et
// la clé reste dans les réglages du téléphone. Le magasin n'a donc pas besoin
// d'un serveur pour que son assistant cherche.
//
// SerpAPI ne rend pas « une liste de liens » : selon la question, Google place
// la réponse dans un encart de réponse directe, une synthèse IA, une fiche
// entité, un comparateur de prix ou un fil d'actualité. Ne lire que
// `organic_results` — ce que faisait la version précédente — revenait à jeter
// précisément le bloc qui contenait le chiffre demandé. On les lit tous, et on
// choisit le moteur d'après l'intention : une question de prix part sur Google
// Shopping, une question d'actualité sur Google News.
//
// Le forfait se compte au mois (100 recherches sur le plan gratuit), pas à la
// minute : chaque appel évité est un appel gagné. D'où le cache et le plafond
// ci-dessous, qui valent bien plus que les millisecondes qu'ils économisent.

const String _endpoint = 'https://serpapi.com/search';

/// Durée pendant laquelle une même question réutilise le résultat déjà payé.
/// Six heures : un prix de matériau ne bouge pas dans la journée, et cela
/// absorbe les questions répétées d'une même session de travail.
const Duration _dureeCache = Duration(hours: 6);

/// L'actualité, elle, se périme en une heure : garder six heures un fil de
/// dépêches donnerait des « nouvelles » déjà dépassées.
const Duration _dureeCacheActu = Duration(hours: 1);

/// Garde-fou : au-delà, on cesse de chercher plutôt que de vider le forfait.
/// Compté depuis le lancement de l'application, ce n'est pas un quota exact —
/// juste un frein contre une boucle qui partirait en vrille.
const int _maxParHeure = 30;

/// Le magasin est à Conakry : « prix du ciment » n'a pas la même réponse ici
/// et à Paris, et une recherche non localisée rend des tarifs européens qui
/// n'ont aucun sens sur le comptoir.
const String _paysParDefaut = 'gn';
const String _langueParDefaut = 'fr';

/// Ce que Google sait faire, et qu'on sait lui demander.
enum MoteurRecherche {
  /// Recherche générale : encart de réponse, synthèse, fiche entité, résultats.
  google('google', 'recherche'),

  /// Comparateur de prix : marchands, tarifs, devises. Le plus utile pour un
  /// magasin qui veut savoir à combien se vend un matériau ailleurs.
  shopping('google_shopping', 'prix'),

  /// Fil de dépêches daté. Pour « qu'est-ce qui se passe sur … ».
  actualites('google_news', 'actualité');

  final String id;
  final String libelle;
  const MoteurRecherche(this.id, this.libelle);
}

/// Une adresse consultée, citée sous la réponse pour que le chiffre soit
/// vérifiable : un prix sans sa source ne vaut pas grand-chose.
@immutable
class SourceWeb {
  final String titre;
  final String url;
  const SourceWeb(this.titre, this.url);
}

@immutable
class ResultatRecherche {
  /// Ce qu'on donne à lire au modèle.
  final String resume;
  final List<SourceWeb> sources;

  /// Le résultat vient du cache : aucune recherche n'a été facturée.
  final bool depuisCache;

  /// Le moteur réellement interrogé, pour l'afficher dans la trace.
  final MoteurRecherche moteur;

  /// Instant exact du relevé. Une source publiée sans date reste incertaine,
  /// mais l'utilisateur sait au moins quand l'assistant l'a vérifiée.
  final DateTime? verifieLe;

  const ResultatRecherche(
    this.resume,
    this.sources, {
    this.depuisCache = false,
    this.moteur = MoteurRecherche.google,
    this.verifieLe,
  });
}

enum CodeErreurRecherche { pasDeCle, auth, quota, reseau, api }

class ErreurRecherche implements Exception {
  final String message;
  final CodeErreurRecherche code;
  ErreurRecherche(this.message, [this.code = CodeErreurRecherche.api]);

  @override
  String toString() => message;
}

class _EntreeCache {
  final DateTime a;
  final ResultatRecherche valeur;
  const _EntreeCache(this.a, this.valeur);
}

// ─── Choix du moteur ──────────────────────────────────────────────────────────

final _motsPrix = RegExp(
    r'\b(prix|tarif|co[uû]te?|combien|acheter|vendre|vendu|devis|cours|'
    r'march[ée]|fournisseur|grossiste|moins cher|budget)\b',
    caseSensitive: false);

final _motsActu = RegExp(
    r'\b(actualit[ée]s?|nouvelle|nouvelles|news|r[ée]cent|derni[eè]re[s]?|'
    r'aujourd|cette semaine|annonce|p[ée]nurie|gr[eè]ve|hausse|baisse)\b',
    caseSensitive: false);

/// Devine ce que la question attend vraiment.
///
/// Une heuristique, pas une science : en cas de doute on reste sur la recherche
/// générale, qui contient de toute façon un encart de prix quand la question en
/// est une. Le prix l'emporte sur l'actualité — « la dernière hausse du prix du
/// ciment » veut d'abord des chiffres.
@visibleForTesting
MoteurRecherche choisirMoteur(String question) {
  if (_motsPrix.hasMatch(question)) return MoteurRecherche.shopping;
  if (_motsActu.hasMatch(question)) return MoteurRecherche.actualites;
  return MoteurRecherche.google;
}

/// Couples moteur+pays que SerpAPI refuse.
///
/// Google Shopping ne couvre pas la Guinée : `gl=gn` lui vaut « Unsupported
/// `gn` country ». Le magasin étant à Conakry, c'était **toutes** les questions
/// de prix qui échouaient — précisément celles qui comptent le plus ici. On
/// pré-inscrit le cas connu, et on apprend les autres au premier refus plutôt
/// que de payer un appel perdu à chaque question.
///
/// Le repli n'est pas une perte : la recherche générale rend elle aussi les
/// encarts de prix, et elle, elle connaît la Guinée.
final Set<String> _combinaisonsRefusees = {'google_shopping|gn'};

final _refusPays = RegExp(
    r'unsupported .*(country|location|domain)|not supported',
    caseSensitive: false);

final _contexteGuinee = RegExp(
  r'\b(guin[ée]e|conakry|gnf|francs? guin[ée]ens?)\b',
  caseSensitive: false,
);

/// Une recherche locale donne des résultats beaucoup plus exploitables que
/// « prix ciment », qui ramène sinon des tarifs européens. On n'altère pas une
/// requête qui cite déjà son marché ou une autre devise : le modèle conserve
/// ainsi la possibilité de comparer une importation à Conakry.
String requeteMarcheGuineen(String question) {
  if (_contexteGuinee.hasMatch(question) ||
      !(_motsPrix.hasMatch(question) || _motsActu.hasMatch(question))) {
    return question;
  }
  return '$question Conakry Guinée prix en GNF';
}

class RechercheWeb {
  final Dio _dio;

  final Map<String, _EntreeCache> _cache = {};
  final List<DateTime> _appels = [];

  RechercheWeb({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  static String _normaliser(String q) =>
      q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool get _quotaLocalDepasse {
    final limite = DateTime.now().subtract(const Duration(hours: 1));
    _appels.removeWhere((a) => a.isBefore(limite));
    return _appels.length >= _maxParHeure;
  }

  /// Recherches déjà payées ce mois-ci, pour l'affichage des réglages.
  int get appelsFacturesRecents => _appels.length;

  /// Interroge Google via SerpAPI et rend de quoi nourrir le modèle.
  ///
  /// [moteur] à `null` laisse l'intention de la question décider. Les résultats
  /// sont cadrés sur la Guinée et le français.
  Future<ResultatRecherche> chercher(
    String question,
    String cle, {
    MoteurRecherche? moteur,
    String pays = _paysParDefaut,
    String langue = _langueParDefaut,
    CancelToken? annulation,
  }) async {
    final questionLocale = requeteMarcheGuineen(question);
    final q = _normaliser(questionLocale);
    if (q.isEmpty) {
      throw ErreurRecherche('Recherche vide.', CodeErreurRecherche.api);
    }
    if (cle.trim().isEmpty) {
      throw ErreurRecherche(
          'Aucune clé SerpAPI enregistrée.', CodeErreurRecherche.pasDeCle);
    }

    var choisi = moteur ?? choisirMoteur(question);
    // Un moteur que SerpAPI refuse pour ce pays ne mérite pas qu'on lui dépense
    // un appel : on retombe tout de suite sur la recherche générale.
    if (_combinaisonsRefusees.contains('${choisi.id}|$pays')) {
      choisi = MoteurRecherche.google;
    }

    final cleCache = '${choisi.id}|$pays|$langue|$q';

    final duree = choisi == MoteurRecherche.actualites
        ? _dureeCacheActu
        : _dureeCache;
    final enCache = _cache[cleCache];
    if (enCache != null && DateTime.now().difference(enCache.a) < duree) {
      return ResultatRecherche(
        enCache.valeur.resume,
        enCache.valeur.sources,
        depuisCache: true,
        moteur: choisi,
        verifieLe: enCache.a,
      );
    }

    if (_quotaLocalDepasse) {
      throw ErreurRecherche(
          'Trop de recherches sur la dernière heure. Réessayez plus tard.',
          CodeErreurRecherche.quota);
    }

    Map donnees;
    var moteurRendu = choisi;
    try {
      donnees = await _appeler(
          questionLocale, cle, choisi, pays, langue, annulation);
    } on ErreurRecherche catch (e) {
      // Refus de la combinaison moteur+pays : on le retient pour ne plus le
      // retenter, et on répond quand même par la recherche générale.
      if (_refusPays.hasMatch(e.message) && choisi != MoteurRecherche.google) {
        _combinaisonsRefusees.add('${choisi.id}|$pays');
        moteurRendu = MoteurRecherche.google;
        donnees = await _appeler(questionLocale, cle,
            MoteurRecherche.google, pays, langue, annulation);
      } else {
        rethrow;
      }
    }

    // Un moteur spécialisé rend parfois zéro résultat là où la recherche
    // générale en a : Google Shopping ne couvre pas la Guinée pour tous les
    // produits. Plutôt que de rendre « aucun résultat » — ce qui pousse le
    // modèle à relancer une recherche et à consommer le forfait deux fois —
    // on bascule tout de suite sur la recherche générale.
    if (moteurRendu != MoteurRecherche.google && _vide(donnees, moteurRendu)) {
      if (!_quotaLocalDepasse) {
        donnees = await _appeler(questionLocale, cle,
            MoteurRecherche.google, pays, langue, annulation);
        moteurRendu = MoteurRecherche.google;
      }
    }

    final brut = extraireResultats(donnees, moteurRendu);
    final valeur = ResultatRecherche(
      brut.resume,
      brut.sources,
      moteur: moteurRendu,
      verifieLe: DateTime.now(),
    );
    _cache[cleCache] = _EntreeCache(DateTime.now(), valeur);
    return valeur;
  }

  bool _vide(Map donnees, MoteurRecherche moteur) => switch (moteur) {
        MoteurRecherche.shopping =>
          (donnees['shopping_results'] as List?)?.isEmpty ?? true,
        MoteurRecherche.actualites =>
          (donnees['news_results'] as List?)?.isEmpty ?? true,
        MoteurRecherche.google => false,
      };

  Future<Map> _appeler(
    String question,
    String cle,
    MoteurRecherche moteur,
    String pays,
    String langue,
    CancelToken? annulation,
  ) async {
    final Response reponse;
    try {
      reponse = await _dio.get(
        _endpoint,
        cancelToken: annulation,
        queryParameters: {
          'q': question,
          'api_key': cle.trim(),
          'engine': moteur.id,
          'hl': langue,
          'gl': pays,
          'num': '10',
          // Sans localisation, Google répond depuis le centre de données qu'il
          // veut : le même « prix du fer à béton » rend des tarifs américains.
          if (moteur != MoteurRecherche.actualites) 'location': 'Guinea',
          // La devise du comparateur. Sans elle, les prix reviennent en dollars
          // et le commerçant doit convertir de tête.
          if (moteur == MoteurRecherche.shopping) 'currency': 'GNF',
        },
        options: Options(
          headers: const {'Accept': 'application/json'},
          // SerpAPI répond 401 ou 429 avec un corps JSON explicite : on veut le
          // lire plutôt que de recevoir une exception muette.
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ErreurRecherche('Le service de recherche est injoignable.',
          CodeErreurRecherche.reseau);
    }

    final donnees = reponse.data;
    final erreur = donnees is Map ? donnees['error']?.toString() : null;
    if (reponse.statusCode != 200 || erreur != null) {
      final message = erreur ?? 'Erreur HTTP ${reponse.statusCode}';

      // SerpAPI signale « aucun résultat » par un champ `error`, pas par un
      // code HTTP : c'est un succès vide, pas une panne.
      if (RegExp("hasn't returned any results|no results",
              caseSensitive: false)
          .hasMatch(message)) {
        return const {};
      }
      if (reponse.statusCode == 401) {
        throw ErreurRecherche('Clé SerpAPI refusée.', CodeErreurRecherche.auth);
      }
      if (reponse.statusCode == 429 ||
          RegExp('run out|exhaust', caseSensitive: false).hasMatch(message)) {
        throw ErreurRecherche('Forfait de recherche épuisé pour ce mois.',
            CodeErreurRecherche.quota);
      }
      throw ErreurRecherche('Recherche impossible : $message');
    }

    _appels.add(DateTime.now());
    return donnees is Map ? donnees : const {};
  }
}

// ─── Extraction ───────────────────────────────────────────────────────────────

String _txt(dynamic v) => v?.toString().trim() ?? '';

/// Coupe sans laisser de phrase pendante au milieu d'un mot.
String _borner(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

/// Réduit la réponse SerpAPI à l'essentiel.
///
/// Le modèle n'a pas besoin du reste, et chaque bloc inutile est du contexte
/// payé pour rien — deux fois : à la recherche, puis au modèle. On lit en
/// revanche *tous* les blocs utiles, du plus décisif au plus accessoire :
/// l'ordre compte, un modèle accorde plus de poids à ce qu'il lit en premier.
ResultatRecherche extraireResultats(Map donnees,
    [MoteurRecherche moteur = MoteurRecherche.google]) {
  final morceaux = <String>[];
  final sources = <SourceWeb>[];

  void source(dynamic titre, dynamic lien) {
    final url = _txt(lien);
    if (url.isEmpty || !url.startsWith('http')) return;
    sources.add(SourceWeb(_txt(titre).isEmpty ? url : _txt(titre), url));
  }

  // ── 1. L'encart de réponse directe ──────────────────────────────────────
  // Quand il existe, c'est presque toujours ce que la question demandait.
  // Google lui donne une dizaine de formes selon le type de question : un
  // nombre, un tableau de conversion, une liste d'étapes. On les couvre.
  final direct = donnees['answer_box'];
  if (direct is Map) {
    final lignes = <String>[];

    final rep = _txt(direct['answer'].toString() == 'null'
        ? null
        : direct['answer'] ?? direct['result'] ?? direct['snippet']);
    if (rep.isNotEmpty && rep != 'null') lignes.add(rep);

    // Conversion de devises : « 1 USD = … GNF ». Le champ utile n'est ni
    // `answer` ni `snippet` mais la paire monnaie/valeur.
    final change = direct['currency'] ?? direct['exchange_rate'];
    if (change != null) lignes.add('Taux : ${_txt(change)}');
    if (direct['price'] != null) lignes.add('Prix : ${_txt(direct['price'])}');

    final liste = direct['list'] ?? direct['snippet_highlighted_words'];
    if (liste is List && liste.isNotEmpty) {
      lignes.add(liste.take(8).map((e) => '· ${_txt(e)}').join('\n'));
    }

    if (lignes.isNotEmpty) {
      morceaux.add('RÉPONSE DIRECTE GOOGLE :\n${lignes.join('\n')}');
    }
    source(direct['title'] ?? 'Réponse Google', direct['link']);
  }

  // ── 2. La synthèse IA de Google ─────────────────────────────────────────
  final apercu = donnees['ai_overview'];
  if (apercu is Map) {
    final blocs = apercu['text_blocks'];
    if (blocs is List) {
      final txt = _aplatirBlocs(blocs);
      if (txt.isNotEmpty) {
        morceaux.add('SYNTHÈSE GOOGLE :\n${_borner(txt, 1200)}');
      }
    }
    final refs = apercu['references'];
    if (refs is List) {
      for (final r in refs.take(4)) {
        if (r is Map) source(r['title'] ?? r['source'], r['link']);
      }
    }
  }

  // ── 3. La fiche entité ──────────────────────────────────────────────────
  // Pour « qui est ce fournisseur », « qu'est-ce que le fer torsadé » : la
  // description et les attributs valent mieux que six extraits de pages.
  final fiche = donnees['knowledge_graph'];
  if (fiche is Map) {
    final lignes = <String>[];
    final titre = _txt(fiche['title']);
    final type = _txt(fiche['type']);
    if (titre.isNotEmpty) {
      lignes.add(type.isEmpty ? titre : '$titre ($type)');
    }
    final desc = _txt(fiche['description']);
    if (desc.isNotEmpty) lignes.add(_borner(desc, 600));

    // Téléphone, adresse, site : exactement ce qu'on cherche sur un fournisseur.
    for (final champ in const ['phone', 'address', 'website', 'hours', 'rating']) {
      final v = _txt(fiche[champ]);
      if (v.isNotEmpty) lignes.add('$champ : $v');
    }
    final attributs = fiche['attributes'];
    if (attributs is Map) {
      for (final e in attributs.entries.take(8)) {
        lignes.add('${e.key} : ${_txt(e.value)}');
      }
    }
    if (lignes.isNotEmpty) morceaux.add('FICHE :\n${lignes.join('\n')}');
    source(fiche['title'], fiche['website'] ?? fiche['source']?['link']);
  }

  // ── 4. Les prix ─────────────────────────────────────────────────────────
  // Le bloc le plus utile à un magasin : ce que le même produit se vend
  // ailleurs, marchand par marchand.
  final produits = donnees['shopping_results'] ?? donnees['inline_shopping_results'];
  if (produits is List && produits.isNotEmpty) {
    final lignes = <String>[];
    for (final p in produits.take(10)) {
      if (p is! Map) continue;
      final bouts = <String>[
        _txt(p['title']),
        if (_txt(p['price']).isNotEmpty) _txt(p['price']),
        if (_txt(p['source']).isNotEmpty) 'chez ${_txt(p['source'])}',
        if (_txt(p['delivery']).isNotEmpty) _txt(p['delivery']),
      ].where((s) => s.isNotEmpty).toList();
      if (bouts.isNotEmpty) lignes.add('· ${bouts.join(' — ')}');
      source(p['title'], p['product_link'] ?? p['link']);
    }
    if (lignes.isNotEmpty) {
      morceaux.add('PRIX RELEVÉS SUR LE MARCHÉ :\n${lignes.join('\n')}');
    }
  }

  // ── 5. L'actualité ──────────────────────────────────────────────────────
  // Datée : sans la date, le modèle présente une dépêche de 2019 comme
  // « récente ».
  final actus = donnees['news_results'] ?? donnees['top_stories'];
  if (actus is List && actus.isNotEmpty) {
    final lignes = <String>[];
    for (final a in actus.take(6)) {
      if (a is! Map) continue;
      final bouts = <String>[
        _txt(a['title']),
        if (_txt(a['snippet']).isNotEmpty) _txt(a['snippet']),
        if (_txt(a['date']).isNotEmpty) '(${_txt(a['date'])})',
        if (_txt(a['source']).isNotEmpty) '— ${_txt(a['source'])}',
      ].where((s) => s.isNotEmpty).toList();
      if (bouts.isNotEmpty) lignes.add('· ${bouts.join(' ')}');
      source(a['title'], a['link']);
    }
    if (lignes.isNotEmpty) {
      morceaux.add('ACTUALITÉS :\n${lignes.join('\n')}');
    }
  }

  // ── 6. Les résultats classiques ─────────────────────────────────────────
  final organiques = donnees['organic_results'];
  if (organiques is List) {
    final lignes = <String>[];
    for (final r in organiques.take(8)) {
      if (r is! Map) continue;
      final bouts = <String>[
        _txt(r['title']),
        if (_txt(r['snippet']).isNotEmpty) _txt(r['snippet']),
        if (_txt(r['date']).isNotEmpty) '(${_txt(r['date'])})',
      ].where((s) => s.isNotEmpty).toList();
      if (bouts.isNotEmpty) lignes.add('· ${bouts.join(' — ')}');
      source(r['title'], r['link']);
    }
    if (lignes.isNotEmpty) {
      morceaux.add('RÉSULTATS :\n${lignes.join('\n')}');
    }
  }

  // ── 7. « Autres questions posées » ──────────────────────────────────────
  // Souvent la réponse exacte à une question voisine que le commerçant
  // n'avait pas pensé à poser. Bon marché : c'est le même appel.
  final connexes = donnees['related_questions'];
  if (connexes is List && connexes.isNotEmpty) {
    final lignes = <String>[];
    for (final c in connexes.take(4)) {
      if (c is! Map) continue;
      final q = _txt(c['question']);
      final r = _txt(c['snippet'] ?? c['answer']);
      if (q.isNotEmpty && r.isNotEmpty) {
        lignes.add('· $q → ${_borner(r, 300)}');
      }
    }
    if (lignes.isNotEmpty) {
      morceaux.add('QUESTIONS VOISINES :\n${lignes.join('\n')}');
    }
  }

  if (morceaux.isEmpty) {
    return ResultatRecherche(
        'Aucun résultat pertinent pour cette recherche.', const [],
        moteur: moteur);
  }

  // La date du jour en tête : un modèle sans repère temporel prend une
  // dépêche « d'il y a 3 jours » pour une information d'il y a trois ans.
  final aujourdhui = DateTime.now().toIso8601String().substring(0, 10);
  return ResultatRecherche(
    'Recherche effectuée le $aujourdhui (moteur : ${moteur.libelle}).\n\n'
    '${morceaux.join('\n\n')}',
    sources,
    moteur: moteur,
  );
}

/// La synthèse IA de Google arrive en blocs imbriqués (paragraphes, listes,
/// sous-listes). À plat, elle se lit d'un trait.
String _aplatirBlocs(List blocs, [int profondeur = 0]) {
  if (profondeur > 3) return '';
  final bouts = <String>[];
  for (final b in blocs) {
    if (b is! Map) continue;
    final t = _txt(b['snippet'] ?? b['text']);
    if (t.isNotEmpty) bouts.add(t);
    final sous = b['list'] ?? b['text_blocks'];
    if (sous is List) {
      final s = _aplatirBlocs(sous, profondeur + 1);
      if (s.isNotEmpty) bouts.add(s);
    }
  }
  return bouts.join(' ');
}

/// Met en forme les adresses consultées pour qu'elles apparaissent sous la
/// réponse, sans doublon et sans en noyer le texte.
String formaterSources(List<SourceWeb> sources) {
  final vues = <String, String>{};
  for (final s in sources) {
    if (s.url.isNotEmpty) {
      vues.putIfAbsent(s.url, () => s.titre.isEmpty ? s.url : s.titre);
    }
  }
  if (vues.isEmpty) return '';
  final lignes =
      vues.entries.take(6).map((e) => '- [${e.value}](${e.key})').join('\n');
  return '\n\n**Sources consultées :**\n$lignes';
}

final rechercheWebProvider = Provider<RechercheWeb>((ref) => RechercheWeb());
