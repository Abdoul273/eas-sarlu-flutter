import 'dart:typed_data';

import 'package:eas_sarlu/features/assistant/ai_client.dart';
import 'package:eas_sarlu/features/assistant/recherche_web.dart';
import 'package:eas_sarlu/features/assistant/voix_neurale.dart';
import 'package:flutter_test/flutter_test.dart';

// Ces tests gardent la panne qui a motivé la reprise du client IA :
// l'assistant répondait « Aucune réponse. » dès qu'une question déclenchait une
// recherche web. Trois causes s'additionnaient, et chacune a son test.

void main() {
  group('Lecture d\'une réponse Gemini', () {
    test('le brouillon de réflexion ne se lit pas', () {
      // La panne exacte : les modèles « latest » réfléchissent, et leur
      // brouillon arrive dans la même liste de parts que la réponse. Le lire
      // livrerait au commerçant un monologue interne à la place de son bilan.
      final texte = ClientIA.texteGemini([
        {'text': 'Je dois consulter le stock puis calculer.', 'thought': true},
        {'text': 'Il reste sept sacs de ciment.'},
      ]);
      expect(texte, 'Il reste sept sacs de ciment.');
    });

    test('une réponse faite d\'un seul appel d\'outil ne rend rien à lire', () {
      // C'est ce cas précis que l'ancien code transformait en « Aucune
      // réponse. ». On veut qu'il rende vide : l'appelant sait alors qu'il doit
      // sommer le modèle de conclure, au lieu d'afficher une bulle inutile.
      final texte = ClientIA.texteGemini([
        {
          'functionCall': {
            'name': 'recherche_web',
            'args': {'requete': 'prix ciment Conakry'},
          },
          'thoughtSignature': 'EpsDCpgDARFNMg…',
        },
      ]);
      expect(texte, isEmpty);
    });

    test('les parts textuelles se recollent dans l\'ordre', () {
      final texte = ClientIA.texteGemini([
        {'text': 'Le chiffre d\'affaires '},
        {'text': 'du jour est de 2 450 000 GNF.'},
      ]);
      expect(texte, 'Le chiffre d\'affaires du jour est de 2 450 000 GNF.');
    });

    test('une liste de parts vide ou biscornue ne fait pas tomber la lecture',
        () {
      expect(ClientIA.texteGemini(const []), isEmpty);
      expect(ClientIA.texteGemini(['pas une map', 42, null]), isEmpty);
    });
  });

  group('Assainissement de la conversation', () {
    test('un tour vide est retiré', () {
      // Claude refuse tout le message (400) quand un bloc de texte est vide :
      // un seul message vide dans l'historique bloquait toute la conversation.
      final tours = ClientIA.assainirTours(const [
        TourIA('user', 'bonjour'),
        TourIA('assistant', '   '),
        TourIA('user', 'et le stock ?'),
      ]);
      expect(tours.map((t) => t.contenu), ['bonjour\n\net le stock ?']);
    });

    test('deux tours de même rôle sont fusionnés', () {
      // Gemini refuse deux « user » consécutifs. Le cas se produisait dès qu'un
      // message d'assistant vide était retiré entre les deux.
      final tours = ClientIA.assainirTours(const [
        TourIA('user', 'combien de ciment'),
        TourIA('user', 'et de fer'),
      ]);
      expect(tours, hasLength(1));
      expect(tours.first.contenu, 'combien de ciment\n\net de fer');
    });

    test('la conversation commence toujours par l\'utilisateur', () {
      // La fenêtre glissante de l'historique (douze messages) pouvait
      // parfaitement s'ouvrir sur une réponse de l'assistant après quelques
      // échanges — ce que Claude rejette.
      final tours = ClientIA.assainirTours(const [
        TourIA('assistant', 'Voici le bilan.'),
        TourIA('user', 'merci, et demain ?'),
      ]);
      expect(tours.first.role, 'user');
      expect(tours, hasLength(1));
    });

    test('un rôle inconnu est traité comme un tour utilisateur', () {
      final tours = ClientIA.assainirTours(const [TourIA('system', 'consigne')]);
      expect(tours.single.role, 'user');
    });

    test('une conversation entièrement vide ne rend aucun tour', () {
      final tours = ClientIA.assainirTours(const [
        TourIA('assistant', ''),
        TourIA('user', '  \n '),
      ]);
      expect(tours, isEmpty);
    });
  });

  group('Choix du moteur de recherche', () {
    test('une question de prix part sur le comparateur', () {
      expect(choisirMoteur('prix du sac de ciment à Conakry'),
          MoteurRecherche.shopping);
      expect(choisirMoteur('combien coûte le fer à béton'),
          MoteurRecherche.shopping);
    });

    test('une question d\'actualité part sur les dépêches', () {
      expect(choisirMoteur('actualités sur la pénurie de ciment'),
          MoteurRecherche.actualites);
    });

    test('le prix l\'emporte sur l\'actualité', () {
      // « La dernière hausse du prix du ciment » veut d'abord des chiffres :
      // un fil de dépêches répondrait à côté.
      expect(choisirMoteur('dernière hausse du prix du ciment'),
          MoteurRecherche.shopping);
    });

    test('le reste passe par la recherche générale', () {
      expect(choisirMoteur('qu\'est-ce que le fer torsadé'),
          MoteurRecherche.google);
    });

    test('la chaîne de repli retire le modèle qui vient d\'échouer', () {
      // L'ancien repli était « flash-lite » — qui est aussi le modèle par
      // défaut. Quand c'était lui qui était à sec, le repli redemandait le
      // modèle épuisé et rendait le même 429. Constaté sur la clé du magasin.
      final chaine = ClientIA.chaineDeRepli('gemini-flash-lite-latest');
      expect(chaine, isNot(contains('gemini-flash-lite-latest')));
      expect(chaine, isNotEmpty);
      expect(ClientIA.chaineDeRepli('gemini-pro-latest').first,
          'gemini-flash-lite-latest');
    });

    test('la Guinée est bien le pays visé par défaut', () {
      // Vérifié en conditions réelles : Google Shopping refuse `gl=gn`
      // (« Unsupported `gn` country »), là où la recherche générale et les
      // actualités l'acceptent. Le repli est donc obligatoire, pas décoratif —
      // sans lui, toutes les questions de prix échouaient.
      expect(MoteurRecherche.shopping.id, 'google_shopping');
      expect(MoteurRecherche.google.id, 'google');
      expect(MoteurRecherche.actualites.id, 'google_news');
    });
  });

  group('Extraction des résultats SerpAPI', () {
    test('l\'encart de réponse directe passe en tête', () {
      final r = extraireResultats(const {
        'answer_box': {
          'answer': '85 000 GNF le sac',
          'title': 'Prix ciment',
          'link': 'https://exemple.gn/ciment',
        },
        'organic_results': [
          {'title': 'Un marchand', 'snippet': 'vend du ciment', 'link': 'https://a.gn'},
        ],
      });
      expect(r.resume, contains('RÉPONSE DIRECTE'));
      expect(r.resume.indexOf('RÉPONSE DIRECTE'),
          lessThan(r.resume.indexOf('RÉSULTATS')));
      expect(r.sources.map((s) => s.url), contains('https://exemple.gn/ciment'));
    });

    test('les prix relevés sont rendus marchand par marchand', () {
      // Le bloc le plus utile à un magasin, et celui que l'ancienne extraction
      // jetait entièrement : elle ne lisait que `organic_results`.
      final r = extraireResultats(const {
        'shopping_results': [
          {
            'title': 'Ciment CIMAF 50 kg',
            'price': '82 000 GNF',
            'source': 'Quincaillerie Diallo',
            'link': 'https://boutique.gn/cimaf',
          },
        ],
      }, MoteurRecherche.shopping);
      expect(r.resume, contains('PRIX RELEVÉS'));
      expect(r.resume, contains('82 000 GNF'));
      expect(r.resume, contains('Quincaillerie Diallo'));
    });

    test('une dépêche garde sa date', () {
      // Sans la date, le modèle présente une dépêche de 2019 comme récente.
      final r = extraireResultats(const {
        'news_results': [
          {
            'title': 'Hausse du ciment',
            'date': 'il y a 2 jours',
            'link': 'https://presse.gn/1',
          },
        ],
      }, MoteurRecherche.actualites);
      expect(r.resume, contains('il y a 2 jours'));
    });

    test('la date du jour accompagne toujours le résultat', () {
      final r = extraireResultats(const {
        'organic_results': [
          {'title': 'x', 'snippet': 'y', 'link': 'https://z.gn'}
        ],
      });
      final aujourdhui = DateTime.now().toIso8601String().substring(0, 10);
      expect(r.resume, contains(aujourdhui));
    });

    test('une réponse SerpAPI vide se dit, sans lever d\'erreur', () {
      final r = extraireResultats(const {});
      expect(r.resume, contains('Aucun résultat'));
      expect(r.sources, isEmpty);
    });

    test('un lien qui n\'en est pas un n\'est pas cité en source', () {
      final r = extraireResultats(const {
        'organic_results': [
          {'title': 'sans lien', 'snippet': 'texte', 'link': 'javascript:void'},
        ],
      });
      expect(r.sources, isEmpty);
    });
  });

  group('Enveloppe WAV de la voix neuronale', () {
    // Gemini rend du PCM brut : sans en-tête, aucun lecteur ne le joue, et le
    // symptôme — « la voix ne marche pas » — ne dit rien de la cause.
    test('l\'en-tête fait 44 octets et annonce les bonnes tailles', () {
      final pcm = Uint8List.fromList(List.filled(100, 0));
      final wav = enveloppeWav(pcm, frequence: 24000);

      expect(wav.length, 144);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final vue = ByteData.sublistView(wav);
      expect(vue.getUint32(4, Endian.little), 136); // taille du fichier − 8
      expect(vue.getUint32(40, Endian.little), 100); // taille des données
      expect(vue.getUint32(24, Endian.little), 24000); // fréquence
      expect(vue.getUint16(22, Endian.little), 1); // mono
      expect(vue.getUint16(34, Endian.little), 16); // 16 bits
      expect(vue.getUint32(28, Endian.little), 48000); // débit en octets/s
    });

    test('les échantillons sont recopiés intacts derrière l\'en-tête', () {
      final pcm = Uint8List.fromList([1, 2, 3, 4]);
      final wav = enveloppeWav(pcm);
      expect(wav.sublist(44), [1, 2, 3, 4]);
    });
  });

  group('Consigne de lecture', () {
    test('le texte à dire suit la consigne, séparé d\'elle', () {
      final c = consigneDeLecture('Le stock est bas.');
      expect(c, endsWith('\n\nLe stock est bas.'));
      expect(c, contains('Ne commente pas'));
    });
  });
}
