import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_config.dart';
import 'recherche_web.dart';

// ─── Couche fournisseurs IA ───────────────────────────────────────────────────
// Transposition de `src/lib/ai.ts` de l'application web : Claude, Gemini, ou un
// relais serveur qui détient seul les clés.
//
// L'appel n'est jamais confié au moteur de synchronisation : l'assistant est
// une fonctionnalité en ligne, il échoue proprement quand le réseau manque
// plutôt que d'encombrer la file d'attente.
//
// ── Pourquoi ce fichier a été repris en entier ────────────────────────────────
// L'assistant répondait « Aucune réponse. » dès la deuxième question. La cause
// n'était ni le quota ni la clé, mais la génération de modèles :
//
//   Les modèles Gemini « latest » réfléchissent avant de répondre. Leur réponse
//   contient alors des parts de réflexion (`thought`, `thoughtSignature`) et,
//   quand ils décident d'appeler un outil, **aucune part de texte**. L'ancien
//   code lisait `parts.map(p => p.text)` : il obtenait une chaîne vide et
//   rendait littéralement « Aucune réponse. ».
//
//   Le déclencheur était la recherche web. `_executerRecherche` ne consultait
//   que le relais serveur — jamais la clé SerpAPI des réglages — et répondait
//   donc toujours « recherche indisponible ». Le modèle reformulait sa
//   recherche, épuisait les allers-retours autorisés, et le dernier tour
//   tombait sur le cas « functionCall sans texte » ci-dessus.
//
// D'où les quatre principes tenus ici :
//   1. Une réponse vide n'est jamais rendue telle quelle : on relance sans
//      outil en exigeant une réponse, et si rien ne vient, on lève une erreur
//      *qui dit pourquoi*. Le commerçant doit pouvoir agir sur ce qu'il lit.
//   2. Les parts de réflexion ne se lisent pas, mais se renvoient intactes :
//      Gemini refuse le tour suivant si la signature manque.
//   3. La recherche passe par SerpAPI avec la clé des réglages, le relais
//      n'étant qu'un recours.
//   4. Tout ce qui est transitoire (5xx, surcharge) se retente avec un délai
//      croissant avant d'être présenté comme une panne.

enum CodeErreurIA { pasDeCle, authentification, quota, reseau, api }

class ErreurIA implements Exception {
  final String message;
  final CodeErreurIA code;
  ErreurIA(this.message, [this.code = CodeErreurIA.api]);

  @override
  String toString() => message;
}

@immutable
class TourIA {
  /// « user » ou « assistant ».
  final String role;
  final String contenu;
  const TourIA(this.role, this.contenu);
}

/// Nombre d'allers-retours de recherche web autorisés pour une même question.
/// Le forfait se compte au mois : mieux vaut une réponse fondée sur quelques
/// recherches ciblées qu'une exploration qui vide le crédit. Le cache de
/// `RechercheWeb` absorbe les reformulations, ce qui permet d'être un peu plus
/// généreux qu'avant sans coûter davantage.
const int _maxRecherches = 4;

/// Codes HTTP qui valent la peine d'être retentés : la panne est passagère.
const Set<int> _statutsRetentables = {408, 500, 502, 503, 504, 529};

/// Nombre de reprises sur erreur transitoire, en plus de l'essai initial.
const int _reprises = 2;

/// Budget de sortie. Les modèles à réflexion consomment une partie de ce budget
/// à penser : à 4096, une analyse financière un peu fournie était coupée en
/// plein milieu — ou n'arrivait jamais, tout le budget étant parti en
/// réflexion.
const int _budgetSortie = 16384;

/// Ce que le modèle doit produire quand on lui coupe les outils : une réponse,
/// tout de suite, avec ce qu'il a.
const String _sommationDeRepondre =
    'Réponds maintenant en français, directement et complètement, avec les '
    'informations dont tu disposes déjà. N\'appelle plus aucun outil et ne '
    'demande pas de recherche supplémentaire. Si une donnée te manque, dis-le '
    'en une phrase puis réponds sur le reste.';

class ClientIA {
  final Dio _dio;
  final RechercheWeb _recherche;

  /// Les sources consultées pendant le dernier appel, pour la trace affichée
  /// sous la réponse.
  final List<SourceWeb> _sources = [];

  ClientIA({Dio? dio, RechercheWeb? recherche})
      : _recherche = recherche ?? RechercheWeb(),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              // Une réponse longue prend du temps à s'écrire : couper à trente
              // secondes tronquait les analyses financières en plein milieu.
              // Les modèles à réflexion sont plus lents encore avant le premier
              // octet, d'où la marge.
              receiveTimeout: const Duration(seconds: 180),
            ));

  /// Envoie la conversation au fournisseur actif et rend le texte brut.
  ///
  /// Une clé épuisée ne doit pas interrompre le commerçant : on retente la même
  /// clé après une courte pause — les quotas Gemini se libèrent à la minute —
  /// puis on passe à la clé suivante.
  Future<String> demander(
    ConfigIA cfg,
    String systeme,
    List<TourIA> tours, {
    CancelToken? annulation,
  }) async {
    _sources.clear();
    final propres = assainirTours(tours);
    if (propres.isEmpty) {
      throw ErreurIA('Aucune question à envoyer.', CodeErreurIA.api);
    }

    if (cfg.relaisActif) {
      return _appelerRelais(cfg, systeme, propres, annulation);
    }

    final cles = cfg.listeCles;
    if (cles.isEmpty) {
      throw ErreurIA('Clé API manquante', CodeErreurIA.pasDeCle);
    }

    ErreurIA? derniere;
    for (final cle in cles) {
      for (var essai = 0; essai < 2; essai++) {
        try {
          final texte = cfg.fournisseur == FournisseurIA.gemini
              ? await _appelerGemini(cfg, cle, systeme, propres, annulation)
              : await _appelerClaude(cfg, cle, systeme, propres, annulation);
          return texte + formaterSources(_sources);
        } on ErreurIA catch (e) {
          derniere = e;
          if (e.code == CodeErreurIA.quota && essai == 0) {
            await Future<void>.delayed(const Duration(seconds: 4));
            continue;
          }
          break; // clé invalide ou erreur définitive → clé suivante
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          derniere = ErreurIA(
              'Impossible de joindre le service IA. Vérifiez votre connexion.',
              CodeErreurIA.reseau);
          break;
        }
      }
    }
    throw derniere ??
        ErreurIA('Impossible de joindre le service IA.', CodeErreurIA.api);
  }

  // ── Hygiène de la conversation ────────────────────────────────────────────

  /// Rend la liste de tours acceptable par les deux API.
  ///
  /// Trois règles, chacune payée par un échec constaté :
  ///   • un tour au contenu vide fait répondre 400 à Claude
  ///     (« text content blocks must be non-empty ») ;
  ///   • deux tours consécutifs de même rôle sont refusés par Gemini ;
  ///   • la conversation doit commencer par l'utilisateur. La fenêtre glissante
  ///     de l'historique peut parfaitement commencer sur une réponse de
  ///     l'assistant — c'est ce qui arrivait après quelques échanges.
  @visibleForTesting
  static List<TourIA> assainirTours(List<TourIA> tours) {
    final propres = <TourIA>[];
    for (final t in tours) {
      final contenu = t.contenu.trim();
      if (contenu.isEmpty) continue;
      final role = t.role == 'assistant' ? 'assistant' : 'user';

      if (propres.isNotEmpty && propres.last.role == role) {
        propres[propres.length - 1] =
            TourIA(role, '${propres.last.contenu}\n\n$contenu');
        continue;
      }
      propres.add(TourIA(role, contenu));
    }

    while (propres.isNotEmpty && propres.first.role == 'assistant') {
      propres.removeAt(0);
    }
    return propres;
  }

  // ── Requêtes HTTP, avec reprise sur incident passager ──────────────────────

  /// Rejoue [envoi] tant que l'échec est transitoire.
  ///
  /// Un 503 « model is overloaded » chez Google ou Anthropic dure quelques
  /// secondes. Le présenter comme une panne obligeait le commerçant à reposer
  /// sa question — ce que fait très bien la machine.
  Future<Response> _avecReprises(
    Future<Response> Function() envoi,
    CancelToken? annulation,
  ) async {
    Object? derniere;
    for (var essai = 0; essai <= _reprises; essai++) {
      try {
        final r = await envoi();
        final statut = r.statusCode ?? 0;
        if (_statutsRetentables.contains(statut) && essai < _reprises) {
          await Future<void>.delayed(
              Duration(milliseconds: 600 * math.pow(2, essai).toInt()));
          continue;
        }
        return r;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        derniere = e;
        final transitoire = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            _statutsRetentables.contains(e.response?.statusCode ?? 0);
        if (!transitoire || essai == _reprises) rethrow;
        await Future<void>.delayed(
            Duration(milliseconds: 600 * math.pow(2, essai).toInt()));
      }
    }
    throw derniere ??
        ErreurIA('Service IA injoignable.', CodeErreurIA.reseau);
  }

  // ── Relais serveur ────────────────────────────────────────────────────────

  Future<String> _appelerRelais(ConfigIA cfg, String systeme,
      List<TourIA> tours, CancelToken? annulation) async {
    try {
      final reponse = await _avecReprises(
        () => _dio.post(
          kRelaisIA,
          cancelToken: annulation,
          data: {
            'provider': cfg.fournisseur.name,
            'model': cfg.modele,
            'system': systeme,
            'turns': [
              for (final t in tours) {'role': t.role, 'content': t.contenu},
            ],
            'recherche': cfg.recherche,
          },
        ),
        annulation,
      );
      final donnees = reponse.data;
      if (donnees is Map && donnees['text'] is String) {
        final texte = (donnees['text'] as String).trim();
        if (texte.isNotEmpty) return texte;
      }
      throw ErreurIA(
          'Le relais IA a répondu sans texte. Vérifiez sa configuration.',
          CodeErreurIA.api);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      final donnees = e.response?.data;
      if (donnees is Map && donnees['error'] is String) {
        throw ErreurIA(donnees['error'] as String,
            _codeDepuisHttp(e.response?.statusCode));
      }
      throw ErreurIA(
          'Impossible de joindre le service IA. Vérifiez votre connexion.',
          CodeErreurIA.reseau);
    }
  }

  CodeErreurIA _codeDepuisHttp(int? statut) => switch (statut) {
        401 || 403 => CodeErreurIA.authentification,
        429 => CodeErreurIA.quota,
        _ => CodeErreurIA.api,
      };

  // ── Claude ────────────────────────────────────────────────────────────────

  Future<String> _appelerClaude(ConfigIA cfg, String cle, String systeme,
      List<TourIA> tours, CancelToken? annulation) async {
    if (cle.isEmpty) {
      throw ErreurIA('Clé API Claude manquante', CodeErreurIA.pasDeCle);
    }

    final outille = cfg.rechercheDisponible;
    final messages = <Map<String, dynamic>>[
      for (final t in tours) {'role': t.role, 'content': t.contenu},
    ];

    for (var tour = 0; tour <= _maxRecherches; tour++) {
      final reponse = await _requeteClaude(
          cfg.modele, cle, systeme, messages, outille, annulation);

      final blocs = (reponse.data['content'] as List?) ?? const [];
      final texte = blocs
          .where((b) => b is Map && b['type'] == 'text')
          .map((b) => b['text'] as String? ?? '')
          .join('\n')
          .trim();

      // Tant que Claude réclame une recherche, on la lui exécute et on lui rend
      // la main ; dès qu'il répond sans outil, la conversation est terminée.
      final demandes = blocs
          .where((b) =>
              b is Map && b['type'] == 'tool_use' && b['name'] == 'recherche_web')
          .toList();

      if (demandes.isEmpty) {
        if (texte.isNotEmpty) return texte;
        // Réponse sans texte ni outil : on somme le modèle de conclure plutôt
        // que de rendre un message vide.
        return _conclureClaude(cfg, cle, systeme, messages, blocs, annulation);
      }

      if (tour == _maxRecherches) {
        return _conclureClaude(cfg, cle, systeme, messages, blocs, annulation);
      }

      messages.add({'role': 'assistant', 'content': blocs});
      messages.add({
        'role': 'user',
        'content': [
          for (final d in demandes)
            {
              'type': 'tool_result',
              'tool_use_id': d['id'],
              'content': await _executerRecherche(
                  cfg, d['input']?['requete']?.toString() ?? '', annulation),
            },
        ],
      });
    }

    throw ErreurIA('Recherche interrompue : trop d\'allers-retours.');
  }

  /// Dernier mot : outils coupés, consigne explicite. Un modèle privé d'outil
  /// répond toujours quelque chose ; c'est ce qui garantit qu'on ne rend jamais
  /// une bulle vide.
  Future<String> _conclureClaude(
    ConfigIA cfg,
    String cle,
    String systeme,
    List<Map<String, dynamic>> messages,
    List blocsPrecedents,
    CancelToken? annulation,
  ) async {
    final fil = [...messages];
    if (blocsPrecedents.isNotEmpty) {
      fil.add({'role': 'assistant', 'content': blocsPrecedents});
      // Un `tool_use` non satisfait rend le message suivant invalide : on
      // ferme chaque appel resté ouvert avant de reprendre la main.
      final ouverts = blocsPrecedents
          .where((b) => b is Map && b['type'] == 'tool_use')
          .toList();
      if (ouverts.isNotEmpty) {
        fil.add({
          'role': 'user',
          'content': [
            for (final o in ouverts)
              {
                'type': 'tool_result',
                'tool_use_id': o['id'],
                'content': 'Limite de recherches atteinte.',
              },
          ],
        });
      }
    }
    fil.add({'role': 'user', 'content': _sommationDeRepondre});

    final reponse =
        await _requeteClaude(cfg.modele, cle, systeme, fil, false, annulation);
    final texte = ((reponse.data['content'] as List?) ?? const [])
        .where((b) => b is Map && b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join('\n')
        .trim();

    if (texte.isNotEmpty) return texte;
    throw ErreurIA(
        'Claude n\'a produit aucun texte (motif : '
        '${reponse.data['stop_reason'] ?? 'inconnu'}). Reformulez votre '
        'question, ou choisissez un autre modèle dans les paramètres.',
        CodeErreurIA.api);
  }

  Future<Response> _requeteClaude(
    String modele,
    String cle,
    String systeme,
    List<Map<String, dynamic>> messages,
    bool outille,
    CancelToken? annulation,
  ) async {
    try {
      final r = await _avecReprises(
        () => _dio.post(
          'https://api.anthropic.com/v1/messages',
          cancelToken: annulation,
          options: Options(
            headers: {
              'content-type': 'application/json',
              'x-api-key': cle,
              'anthropic-version': '2023-06-01',
            },
            validateStatus: (_) => true,
          ),
          data: {
            'model': modele,
            'max_tokens': _budgetSortie,
            'system': systeme,
            if (outille) 'tools': [_outilRechercheClaude],
            'messages': messages,
          },
        ),
        annulation,
      );
      if ((r.statusCode ?? 0) != 200) throw _erreurCorps(r, 'Claude');
      return r;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _erreurHttp(e, 'Claude');
    }
  }

  static const _outilRechercheClaude = {
    'name': 'recherche_web',
    'description':
        'Recherche sur le web des informations à jour : prix du marché des matériaux, '
            'taux de change, coordonnées de fournisseurs, actualité du secteur. '
            'À n\'utiliser que si la réponse dépend d\'une information récente ou '
            'externe au magasin ; les données du magasin sont déjà fournies.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'requete': {
          'type': 'string',
          'description':
              'La recherche à effectuer, formulée comme sur Google (mots-clés précis, en français).',
        },
      },
      'required': ['requete'],
    },
  };

  // ── Gemini ────────────────────────────────────────────────────────────────

  Future<String> _appelerGemini(ConfigIA cfg, String cle, String systeme,
      List<TourIA> tours, CancelToken? annulation) async {
    if (cle.isEmpty) {
      throw ErreurIA('Clé API Gemini manquante.', CodeErreurIA.pasDeCle);
    }

    // Le quota gratuit se compte par jour **et par modèle**. L'ancien code
    // repliait sur « flash-lite » — qui est aussi le modèle par défaut : quand
    // c'était lui qui était à sec, le repli redemandait le modèle épuisé et
    // rendait le même 429. Vérifié sur la clé du magasin, flash-lite épuisé et
    // flash encore disponible. D'où une chaîne, et non un repli unique.
    final repli = _chaineDeRepli(cfg.modele);
    final outille = cfg.rechercheDisponible;

    final contenus = <Map<String, dynamic>>[
      for (final t in tours)
        {
          'role': t.role == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': t.contenu}
          ],
        },
    ];

    var modeleCourant = cfg.modele;

    for (var tour = 0; tour <= _maxRecherches; tour++) {
      // `_requeteGemini` accepte tous les statuts et lève sur panne réseau : la
      // réponse est donc toujours là, et c'est le statut qu'on examine.
      var reponse = await _requeteGemini(
          modeleCourant, cle, systeme, contenus, outille, annulation);

      var statut = reponse.statusCode ?? 0;

      // Un modèle qui refuse la déclaration d'outil ne doit pas priver le
      // commerçant de sa réponse : on rejoue sans, il répondra de mémoire.
      if (statut == 400 && outille) {
        final sansOutil = await _requeteGemini(
            modeleCourant, cle, systeme, contenus, false, annulation);
        if ((sansOutil.statusCode ?? 0) == 200) {
          reponse = sansOutil;
          statut = 200;
        }
      }
      // Quota épuisé sur le modèle choisi : on descend la chaîne jusqu'à en
      // trouver un qui réponde, et on **reste dessus** pour les tours suivants
      // — repasser sur le modèle épuisé au tour d'après ne ferait que
      // redemander un 429.
      if (statut == 429) {
        for (final candidat in repli) {
          if (candidat == modeleCourant) continue;
          final surRepli = await _requeteGemini(
              candidat, cle, systeme, contenus, outille, annulation);
          if ((surRepli.statusCode ?? 0) == 200) {
            reponse = surRepli;
            statut = 200;
            modeleCourant = candidat;
            break;
          }
        }
      }

      if (statut != 200) throw _erreurCorps(reponse, 'Gemini');

      final candidat = (reponse.data['candidates'] as List?)?.firstOrNull;
      if (candidat == null) {
        final blocage = reponse.data['promptFeedback']?['blockReason'];
        if (blocage != null) {
          throw ErreurIA(
              'Requête bloquée par Gemini ($blocage). Reformulez la question.',
              CodeErreurIA.api);
        }
        throw ErreurIA(
            'Gemini n\'a renvoyé aucune réponse. Réessayez dans un instant.',
            CodeErreurIA.api);
      }

      final parts = (candidat['content']?['parts'] as List?) ?? const [];
      final appels = parts
          .where((p) =>
              p is Map && p['functionCall']?['name'] == 'recherche_web')
          .toList();

      if (appels.isEmpty) {
        final texte = texteGemini(parts);
        if (texte.isNotEmpty) return texte;
        // Le cas qui rendait « Aucune réponse. » : réflexion seule, budget
        // épuisé (`MAX_TOKENS`), ou appel d'un outil inconnu. On conclut.
        return _conclureGemini(cfg, modeleCourant, repli, cle, systeme,
            contenus, parts, candidat['finishReason']?.toString(), annulation);
      }

      if (tour == _maxRecherches) {
        return _conclureGemini(cfg, modeleCourant, repli, cle, systeme,
            contenus, parts, candidat['finishReason']?.toString(), annulation);
      }

      // Les parts sont renvoyées **telles quelles**, réflexion comprise : les
      // modèles Gemini 3 refusent la suite de la conversation si la
      // `thoughtSignature` qui accompagne leur appel d'outil ne leur revient
      // pas. C'est aussi pour cela qu'on ne filtre qu'à la lecture.
      contenus.add({'role': 'model', 'parts': parts});
      contenus.add({
        'role': 'user',
        'parts': [
          for (final a in appels)
            {
              'functionResponse': {
                'name': 'recherche_web',
                'response': {
                  'resultats': await _executerRecherche(
                      cfg,
                      a['functionCall']?['args']?['requete']?.toString() ?? '',
                      annulation),
                },
              },
            },
        ],
      });
    }

    throw ErreurIA('Recherche interrompue : trop d\'allers-retours.');
  }

  /// Les modèles à essayer quand celui choisi rend 429, du plus généreux en
  /// quota gratuit au plus fin. Le modèle courant en est retiré : c'est
  /// précisément lui qui vient d'échouer.
  @visibleForTesting
  static List<String> chaineDeRepli(String modele) => [
        for (final m in const [
          'gemini-flash-lite-latest',
          'gemini-3.5-flash-lite',
          'gemini-flash-latest',
          'gemini-2.5-flash',
        ])
          if (m != modele) m,
      ];

  List<String> _chaineDeRepli(String modele) => chaineDeRepli(modele);

  /// Le texte lisible d'une réponse Gemini.
  ///
  /// Les parts marquées `thought` sont le brouillon interne du modèle : les
  /// afficher livrerait au commerçant un monologue en anglais à la place de sa
  /// réponse.
  @visibleForTesting
  static String texteGemini(List parts) => parts
      .where((p) => p is Map && p['thought'] != true && p['text'] is String)
      .map((p) => p['text'] as String)
      .join()
      .trim();

  /// Dernier mot côté Gemini : outils coupés, consigne explicite, et un budget
  /// relevé si la réflexion avait tout mangé.
  Future<String> _conclureGemini(
    ConfigIA cfg,
    String modele,
    List<String> repli,
    String cle,
    String systeme,
    List<Map<String, dynamic>> contenus,
    List partsPrecedentes,
    String? motifArret,
    CancelToken? annulation,
  ) async {
    final fil = [...contenus];
    if (partsPrecedentes.isNotEmpty) {
      fil.add({'role': 'model', 'parts': partsPrecedentes});
      // Un appel d'outil laissé sans réponse invalide le tour suivant.
      for (final p in partsPrecedentes) {
        if (p is Map && p['functionCall'] != null) {
          fil.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': p['functionCall']['name'],
                  'response': {
                    'resultats': 'Limite de recherches atteinte.',
                  },
                },
              },
            ],
          });
        }
      }
    }
    fil.add({
      'role': 'user',
      'parts': [
        {'text': _sommationDeRepondre}
      ],
    });

    var reponse =
        await _requeteGemini(modele, cle, systeme, fil, false, annulation);

    // Modèle épuisé au dernier moment : un autre garde presque toujours du
    // quota, et rendre une erreur ici gâcherait tout le travail déjà fait.
    if ((reponse.statusCode ?? 0) == 429) {
      for (final candidat in repli) {
        if (candidat == modele) continue;
        final surRepli =
            await _requeteGemini(candidat, cle, systeme, fil, false, annulation);
        if ((surRepli.statusCode ?? 0) == 200) {
          reponse = surRepli;
          break;
        }
      }
    }
    if ((reponse.statusCode ?? 0) != 200) {
      throw _erreurCorps(reponse, 'Gemini');
    }

    final candidat = (reponse.data['candidates'] as List?)?.firstOrNull;
    final parts = (candidat?['content']?['parts'] as List?) ?? const [];
    final texte = texteGemini(parts);
    if (texte.isNotEmpty) return texte;

    final motif = candidat?['finishReason']?.toString() ?? motifArret;
    throw ErreurIA(
      switch (motif) {
        'MAX_TOKENS' =>
          'Le modèle a épuisé son budget de génération avant d\'écrire sa '
              'réponse. Posez une question plus précise, ou choisissez un '
              'modèle « Flash Lite » dans les paramètres : il réfléchit moins '
              'longtemps.',
        'SAFETY' || 'PROHIBITED_CONTENT' =>
          'Gemini a refusé de répondre à cette question. Reformulez-la.',
        'RECITATION' =>
          'Gemini a interrompu sa réponse (citation trop longue). Reformulez '
              'votre question.',
        _ => 'Gemini n\'a produit aucun texte (motif : ${motif ?? 'inconnu'}). '
            'Réessayez, ou changez de modèle dans les paramètres.',
      },
      CodeErreurIA.api,
    );
  }

  Future<Response> _requeteGemini(
    String modele,
    String cle,
    String systeme,
    List<Map<String, dynamic>> contenus,
    bool recherche,
    CancelToken? annulation,
  ) async {
    try {
      return await _avecReprises(
        () => _dio.post(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '${Uri.encodeComponent(modele)}:generateContent',
          cancelToken: annulation,
          // La clé passe par l'en-tête plutôt que par l'URL : les clés de
          // dernière génération (`AQ.…`) sont acceptées des deux façons, mais
          // une clé dans une URL finit dans les journaux du premier
          // intermédiaire venu.
          options: Options(
            headers: {
              'content-type': 'application/json',
              'x-goog-api-key': cle,
            },
            validateStatus: (_) => true,
          ),
          data: {
            'systemInstruction': {
              'parts': [
                {'text': systeme}
              ]
            },
            'contents': contenus,
            if (recherche)
              'tools': [
                {
                  'function_declarations': [
                    {
                      'name': 'recherche_web',
                      'description': _outilRechercheClaude['description'],
                      'parameters': _outilRechercheClaude['input_schema'],
                    }
                  ]
                }
              ],
            'generationConfig': {
              'maxOutputTokens': _budgetSortie,
              'temperature': 0.4,
              'topP': 0.95,
            },
          },
        ),
        annulation,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _erreurHttp(e, 'Gemini');
    }
  }

  // ── Commun ────────────────────────────────────────────────────────────────

  /// Erreur lue dans le corps d'une réponse dont on a accepté tous les statuts.
  ErreurIA _erreurCorps(Response reponse, String fournisseur) {
    final statut = reponse.statusCode;
    var message = 'Erreur HTTP ${statut ?? ''}';
    final donnees = reponse.data;
    if (donnees is Map) {
      final err = donnees['error'];
      if (err is Map) {
        message = err['message']?.toString() ?? message;
      } else if (err is String) {
        message = err;
      }
    }
    return _classer(statut, message, fournisseur);
  }

  ErreurIA _erreurHttp(DioException e, String fournisseur) {
    final statut = e.response?.statusCode;
    var message = 'Erreur HTTP ${statut ?? ''}';
    final donnees = e.response?.data;
    if (donnees is Map && donnees['error'] is Map) {
      message = donnees['error']['message']?.toString() ?? message;
    }

    if (statut == null) {
      return ErreurIA(
          'Impossible de joindre $fournisseur. Vérifiez votre connexion internet.',
          CodeErreurIA.reseau);
    }
    return _classer(statut, message, fournisseur);
  }

  ErreurIA _classer(int? statut, String message, String fournisseur) {
    final bas = message.toLowerCase();
    if (statut == 401 || statut == 403 || bas.contains('api key')) {
      return ErreurIA('Clé $fournisseur invalide : $message',
          CodeErreurIA.authentification);
    }
    if (statut == 429 || message.contains('RESOURCE_EXHAUSTED')) {
      return ErreurIA(
          'Quota de requêtes atteint sur cette clé $fournisseur. '
          'Patientez quelques minutes et réessayez, ou ajoutez une seconde clé '
          'séparée par une virgule dans les paramètres.',
          CodeErreurIA.quota);
    }
    if (statut == 404 && bas.contains('model')) {
      return ErreurIA(
          'Le modèle choisi n\'existe plus chez $fournisseur. Choisissez-en un '
          'autre dans Paramètres → Assistant IA.',
          CodeErreurIA.api);
    }
    if (_statutsRetentables.contains(statut ?? 0)) {
      return ErreurIA(
          '$fournisseur est momentanément surchargé. Réessayez dans quelques '
          'instants.',
          CodeErreurIA.reseau);
    }
    return ErreurIA('Erreur $fournisseur ($statut) : $message');
  }

  /// Exécute la recherche demandée par le modèle.
  ///
  /// Deux chemins, dans cet ordre : la clé SerpAPI des réglages — un téléphone
  /// peut appeler SerpAPI directement, contrairement à un navigateur — puis le
  /// relais serveur s'il est déployé. Sans l'un ni l'autre, on le dit au modèle
  /// plutôt que de le laisser inventer : il répond alors avec ce qu'il sait, en
  /// le signalant.
  Future<String> _executerRecherche(
      ConfigIA cfg, String requete, CancelToken? annulation) async {
    if (requete.trim().isEmpty) {
      return 'Recherche vide : reformule ta requête ou réponds sans donnée web.';
    }

    final cleSerp = cfg.cleSerpapi.trim();
    if (cleSerp.isNotEmpty) {
      try {
        final r = await _recherche.chercher(requete, cleSerp,
            annulation: annulation);
        _sources.addAll(r.sources);
        final instant = r.verifieLe?.toLocal().toIso8601String() ?? 'inconnu';
        return '''${r.resume}

QUALITÉ DU RELEVÉ : recherche ${r.depuisCache ? 'mise en cache' : 'effectuée'} le $instant ; moteur ${r.moteur.libelle} ; ${r.sources.length} source(s) citée(s).
RÈGLE : ne présente pas ce relevé comme un prix certain s'il ne donne pas une date de publication, un lieu ou une source locale. Pour une recommandation d'achat ou de prix, exige au moins deux sources indépendantes récentes ; sinon indique « à confirmer par devis fournisseur ».''';
      } on ErreurRecherche catch (e) {
        // Une clé refusée ou un forfait épuisé sont des faits que le modèle
        // doit connaître : il annoncera au commerçant qu'il répond sans web,
        // au lieu de prétendre avoir vérifié.
        return 'Recherche impossible : ${e.message} '
            'Réponds sans donnée web et précise-le clairement.';
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) rethrow;
        return 'Recherche indisponible ($e). Réponds sans donnée web et '
            'précise-le clairement.';
      }
    }

    if (kRelaisIA.isEmpty) {
      return 'Recherche web non configurée : aucune clé SerpAPI dans les '
          'réglages. Réponds sans donnée web et précise-le clairement.';
    }
    try {
      final reponse = await _dio.post('$kRelaisIA/recherche',
          cancelToken: annulation, data: {'requete': requete});
      final donnees = reponse.data;
      final resume = donnees is Map ? donnees['resume'] : null;
      if (donnees is Map && donnees['sources'] is List) {
        for (final s in donnees['sources'] as List) {
          if (s is Map) {
            _sources.add(SourceWeb(
                s['titre']?.toString() ?? '', s['url']?.toString() ?? ''));
          }
        }
      }
      return resume?.toString() ??
          'Recherche sans résultat exploitable. Réponds sans donnée web et précise-le.';
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      return 'Recherche indisponible ($e). Réponds sans donnée web et précise-le clairement.';
    }
  }
}

final clientIAProvider = Provider<ClientIA>(
    (ref) => ClientIA(recherche: ref.watch(rechercheWebProvider)));
