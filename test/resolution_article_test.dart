// Reconnaître un article dans une phrase de comptoir.
//
// Les cas rassemblés ici sont ceux qui coûtent de l'argent au magasin quand ils
// tournent mal : le doublon (« cornière 30 » crée une deuxième cornière 30) et
// la confusion (une entrée de stock de galva atterrit sur la noire). Chacun est
// écrit avec le vocabulaire réel du dépôt, pas avec des noms d'articles de test.

import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/features/assistant/resolution_article.dart';
import 'package:flutter_test/flutter_test.dart';

Article _art(
  String id,
  String ref,
  String nom, {
  String categorie = '',
  String unite = 'Barre',
  int stock = 10,
  double? longueur,
  double epaisseur = 0,
}) =>
    Article(
      id: id,
      ref: ref,
      nom: nom,
      categorie: categorie,
      unite: unite,
      stock: stock,
      stockMin: 5,
      prixAchat: 100000,
      prixVente: 130000,
      longueur: longueur,
      epaisseur: epaisseur,
    );

/// Un extrait fidèle du catalogue du magasin.
final _catalogue = <Article>[
  _art('a1', 'L-2525-3', 'Cornière L 25×25×3 mm (6 m)',
      categorie: 'Cornière', longueur: 6, epaisseur: 3),
  _art('a2', 'L-3030-3', 'Cornière L 30×30×3 mm (6 m)',
      categorie: 'Cornière', longueur: 6, epaisseur: 3),
  _art('a3', 'L-4040-4', 'Cornière L 40×40×4 mm (6 m)',
      categorie: 'Cornière', longueur: 6, epaisseur: 4),
  _art('a4', 'TC-4040-20', 'Tube carré 40×40 e=2 mm (6 m)',
      categorie: 'Tube carré', longueur: 6, epaisseur: 2),
  _art('a5', 'TC-4040-30', 'Tube carré 40×40 e=3 mm (6 m)',
      categorie: 'Tube carré', longueur: 6, epaisseur: 3),
  _art('a6', 'TON-2MM', 'Tôle noire 2 mm (2000×1000 mm)',
      categorie: 'Tôle noire', unite: 'Plaque', epaisseur: 2),
  _art('a7', 'TOG-1MM', 'Tôle galvanisée 1 mm (1250×2500 mm)',
      categorie: 'Tôle galvanisée', unite: 'Plaque', epaisseur: 1),
  _art('a8', 'HA-012', 'Fer à béton HA Ø12 (12 m)',
      categorie: 'Fer à béton', longueur: 12, epaisseur: 12),
  _art('a9', 'IPN-120', 'Poutrelle IPN 120 (12 m)',
      categorie: 'IPN', longueur: 12, epaisseur: 5.1),
];

void main() {
  group('lecture de la désignation', () {
    test('une cornière dictée à l\'oral se décompose', () {
      final s = extraireSpec('cornière 30×30×3 galva 6m');
      expect(s.famille, 'Cornière');
      expect(s.dimensions, [30, 30, 3]);
      expect(s.epaisseur, 3);
      expect(s.longueur, 6);
      expect(s.finition, 'galvanisé');
    });

    test('la virgule décimale et le signe × du magasin sont acceptés', () {
      final s = extraireSpec('tôle galva 1,5 mm');
      expect(s.famille, 'Tôle galvanisée');
      expect(s.epaisseur, 1.5);
    });

    test('« cornière 30 » laisse la cote sans savoir laquelle', () {
      final s = extraireSpec('cornière 30');
      expect(s.famille, 'Cornière');
      expect(s.nombresLibres, [30]);
      expect(s.dimensions, isEmpty);
    });
  });

  group('l\'article existe déjà', () {
    test('« 10 barres de cornière 30 » retrouve la cornière 30×30×3', () {
      final r = resoudreArticle(_catalogue, 'cornière 30');
      expect(r.verdict, VerdictArticle.exact);
      expect(r.article?.ref, 'L-3030-3');
    });

    test('la référence exacte court-circuite tout', () {
      final r = resoudreArticle(_catalogue, 'L-4040-4');
      expect(r.verdict, VerdictArticle.exact);
      expect(r.article?.ref, 'L-4040-4');
    });

    test('le nom complet du catalogue est reconnu', () {
      final r = resoudreArticle(_catalogue, 'Cornière L 25×25×3 mm (6 m)');
      expect(r.verdict, VerdictArticle.exact);
      expect(r.article?.ref, 'L-2525-3');
    });

    test('la consigne remise au modèle interdit d\'en créer un deuxième', () {
      final r = resoudreArticle(_catalogue, 'cornière 30');
      final texte = expliquerResolution(r);
      expect(texte, contains('EXISTE DÉJÀ'));
      expect(texte, contains('addStock'));
      expect(texte, contains('"articleId":"a2"'));
    });
  });

  group('deux articles se valent : il faut demander', () {
    test('« tube carré 40 » ne tranche pas entre 2 mm et 3 mm', () {
      final r = resoudreArticle(_catalogue, 'tube carré 40');
      expect(r.verdict, VerdictArticle.ambigu);
      expect(r.candidats.map((c) => c.article.ref),
          containsAll(['TC-4040-20', 'TC-4040-30']));
    });

    test('l\'épaisseur dite lève l\'ambiguïté', () {
      final r = resoudreArticle(_catalogue, 'tube carré 40x40 e=3');
      expect(r.verdict, VerdictArticle.exact);
      expect(r.article?.ref, 'TC-4040-30');
    });

    test('la consigne interdit de choisir à la place du commerçant', () {
      final texte = expliquerResolution(resoudreArticle(_catalogue, 'tube carré 40'));
      expect(texte, contains('NE CHOISIS PAS'));
      expect(texte, contains('Pose UNE question'));
    });
  });

  group('la finition fait un autre article', () {
    test('une tôle galva demandée en noire n\'est pas la même tôle', () {
      final r = resoudreArticle(_catalogue, 'tôle noire 1 mm');
      // La noire du catalogue est en 2 mm, la 1 mm est galvanisée : dans les
      // deux cas quelque chose diffère, donc rien ne se mouvemente tout seul.
      expect(r.verdict, isNot(VerdictArticle.exact));
    });

    test('une cornière 30 en inox est une variante à créer', () {
      final r = resoudreArticle(_catalogue, 'cornière 30 inox');
      expect(r.verdict, VerdictArticle.variante);
      expect(r.candidats.first.article.ref, 'L-3030-3');
      expect(r.candidats.first.conflits.join(), contains('inox'));
    });

    test('la consigne renvoie vers une création confirmée, pas automatique', () {
      final texte =
          expliquerResolution(resoudreArticle(_catalogue, 'cornière 30 inox'));
      expect(texte, contains('DEMANDE-LUI'));
      expect(texte, contains('confirmerNouveau'));
    });

    test('le noir non écrit au catalogue est une question, pas un refus', () {
      final r = resoudreArticle(_catalogue, 'cornière 30 noire');
      expect(r.verdict, VerdictArticle.exact);
      expect(r.article?.ref, 'L-3030-3');
      expect(r.imprecisions.join(), contains('finition'));
      expect(expliquerResolution(r), contains('hypothèse'));
    });
  });

  group('rien de connu', () {
    test('une famille absente du dépôt ne ressemble à rien', () {
      final r = resoudreArticle(_catalogue, 'sac de ciment 50 kg');
      expect(r.verdict, VerdictArticle.aucun);
    });

    test('la consigne exige une confirmation avant création', () {
      final texte =
          expliquerResolution(resoudreArticle(_catalogue, 'sac de ciment 50 kg'));
      expect(texte, contains('n\'existe pas encore'));
      expect(texte, contains('confirmerNouveau'));
    });
  });

  group('doublons à la création', () {
    test('créer « Cornière 30x30x3 » signale la référence existante', () {
      final semblables = articlesSemblables(_catalogue, 'Cornière 30x30x3 (6m)');
      expect(semblables, isNotEmpty);
      expect(semblables.first.article.ref, 'L-3030-3');
    });

    test('un article franchement nouveau ne signale rien', () {
      expect(articlesSemblables(_catalogue, 'Ciment Diamond 42,5 sac 50 kg'),
          isEmpty);
    });
  });

  test('un fer à béton se reconnaît par son diamètre', () {
    final r = resoudreArticle(_catalogue, 'fer à béton HA 12');
    expect(r.verdict, VerdictArticle.exact);
    expect(r.article?.ref, 'HA-012');
  });

  test('une famille différente n\'est jamais un candidat', () {
    final r = resoudreArticle(_catalogue, 'IPN 120');
    expect(r.verdict, VerdictArticle.exact);
    expect(r.article?.ref, 'IPN-120');
  });
}
