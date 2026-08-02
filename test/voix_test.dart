// Vérifie ce que la voix prononce réellement.
//
// Les réponses de l'assistant sont écrites en Markdown : lues telles quelles,
// elles donnent « astérisque astérisque marge astérisque astérisque » et des
// tableaux ânonnés barre par barre. Ce fichier tient la liste de ce qui doit
// disparaître avant d'atteindre le haut-parleur.
import 'package:eas_sarlu/features/assistant/voix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nettoyage avant lecture', () {
    test('le gras et l\'italique ne se prononcent pas', () {
      expect(nettoyerPourLecture('La **marge** est _faible_.'),
          'La marge est faible.');
    });

    test('les titres perdent leurs dièses', () {
      expect(nettoyerPourLecture('## Trésorerie\nElle tient.'),
          'Trésorerie\nElle tient.');
    });

    test('les puces perdent leur tiret', () {
      expect(nettoyerPourLecture('- Ciment\n- Fer\n1. Sable'),
          'Ciment\nFer\nSable');
    });

    test('un lien garde son libellé et perd son adresse', () {
      expect(nettoyerPourLecture('Voir [le rapport](https://exemple.gn/x).'),
          'Voir le rapport.');
    });

    test('un bloc de code est annoncé, pas épelé', () {
      final lu = nettoyerPourLecture('Avant\n```dart\nvar x = 1;\n```\nAprès');
      expect(lu, contains('bloc de code'));
      expect(lu, isNot(contains('var x')));
    });

    test('le code court garde son texte sans ses accents graves', () {
      expect(nettoyerPourLecture('Le champ `total` est vide.'),
          'Le champ total est vide.');
    });

    test('un tableau se lit en phrases, sans sa ligne de séparation', () {
      const markdown = '''
| Article | Stock |
|---------|-------|
| Ciment  | 42    |
| Fer     | 7     |
''';
      final lu = nettoyerPourLecture(markdown);
      expect(lu, 'Article, Stock.\nCiment, 42.\nFer, 7.');
      expect(lu, isNot(contains('|')));
      expect(lu, isNot(contains('-')));
    });

    test('les nombres et la ponctuation restent intacts', () {
      expect(
        nettoyerPourLecture(
            '**Total : 2 450 000 GNF** — soit 12,5 % de plus qu\'hier.'),
        'Total : 2 450 000 GNF — soit 12,5 % de plus qu\'hier.',
      );
    });

    test('un texte sans balisage traverse sans être abîmé', () {
      const phrase = 'Le stock de ciment tient encore trois jours.';
      expect(nettoyerPourLecture(phrase), phrase);
    });

    test('un message vide ou purement décoratif ne fait rien dire', () {
      expect(nettoyerPourLecture('   '), isEmpty);
      expect(nettoyerPourLecture('---'), isEmpty);
    });
  });

  // Ce qui reste après le nettoyage s'affiche bien mais s'entend mal : une
  // somme coupée en trois nombres, un sigle épelé, une ligne sans point qui se
  // dit sur un ton resté en l'air.
  group('Préparation de la prosodie', () {
    test('une somme se dit d\'un seul tenant, en francs', () {
      expect(preparerProsodie('Total : 2 450 000 GNF'),
          'Total : 2450000 francs guinéens.');
    });

    test('l\'espace insécable des milliers disparaît aussi', () {
      expect(preparerProsodie('12 000 000 FG.'),
          '12000000 francs guinéens.');
    });

    test('un nombre isolé garde ses décimales', () {
      expect(preparerProsodie('Marge de 12,5 %.'), 'Marge de 12,5 pour cent.');
    });

    test('les sigles du métier se prononcent', () {
      expect(preparerProsodie('Le CA recule.'), "Le chiffre d'affaires recule.");
    });

    test('une date se dit, elle ne s\'épelle pas', () {
      expect(preparerProsodie('Arrêté au 01/08/2026.'), 'Arrêté au 1 août 2026.');
      // Un mois impossible n'est pas une date : on n'y touche pas.
      expect(preparerProsodie('Réf 20/34/2026.'), 'Réf 20/34/2026.');
    });

    test('un emoji ne se prononce pas', () {
      expect(preparerProsodie('Stock bas ⚠️ ciment'), 'Stock bas ciment.');
    });

    test('chaque ligne redescend sur une ponctuation', () {
      expect(preparerProsodie('Trésorerie\nElle tient'), 'Trésorerie.\nElle tient.');
      expect(preparerProsodie('Bilan :\nRien à signaler.'),
          'Bilan :\nRien à signaler.');
    });

    test('le tiret cadratin devient une virgule', () {
      expect(preparerProsodie('Sept sacs — c\'est peu.'),
          "Sept sacs, c'est peu.");
    });
  });
}
