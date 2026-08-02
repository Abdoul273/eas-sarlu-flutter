// Garde-fou contre le retour des « RenderFlex overflowed by N pixels ».
//
// Ces composants sont affichés dans des emplacements de taille fixe (bande de
// tuiles du tableau de bord, cartes de liste). On les soumet ici aux cas
// extrêmes — montants très longs, libellés à rallonge, écran étroit, police
// système agrandie — et on vérifie qu'aucune exception de rendu n'est levée.
import 'package:eas_sarlu/app/theme.dart';
import 'package:eas_sarlu/app/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Enveloppe le sujet dans un vrai thème de l'application.
Widget _hote(Widget enfant, {TextScaler echelle = TextScaler.noScaling}) {
  return MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: echelle),
        child: Center(child: enfant),
      ),
    ),
  );
}

void main() {
  // Montant volontairement démesuré : c'est le cas qui faisait passer la
  // valeur sur une seconde ligne et débordait la tuile de 40 px.
  const montantEnorme = '999 999 999 999 GNF';

  group('StatTile tient dans la bande du tableau de bord', () {
    testWidgets('avec un montant très long', (tester) async {
      await tester.pumpWidget(_hote(
        const SizedBox(
          width: kLargeurStatTile,
          height: kHauteurStatTile,
          child: StatTile(
            libelle: 'Chiffre d\'affaires du jour',
            valeur: montantEnorme,
            sousTitre: '128 ventes enregistrées',
            icone: Icons.point_of_sale_rounded,
            variation: -12.5,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('avec la police système agrandie', (tester) async {
      await tester.pumpWidget(_hote(
        const SizedBox(
          width: kLargeurStatTile,
          height: kHauteurStatTile,
          child: StatTile(
            libelle: 'Encaissements',
            valeur: montantEnorme,
            sousTitre: 'Reçus aujourd\'hui',
            icone: Icons.payments_rounded,
          ),
        ),
        // Borne haute appliquée par le `builder` de MaterialApp dans main.dart.
        echelle: const TextScaler.linear(1.3),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans icône ni sous-titre', (tester) async {
      await tester.pumpWidget(_hote(
        const SizedBox(
          width: kLargeurStatTile,
          height: kHauteurStatTile,
          child: StatTile(libelle: 'Valeur stock', valeur: montantEnorme),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('Composants de liste sur écran étroit', () {
    testWidgets('BadgePastille tronque un libellé trop long', (tester) async {
      await tester.pumpWidget(_hote(
        const SizedBox(
          width: 70,
          child: BadgePastille(
            texte: 'Partiellement réglée depuis hier',
            couleur: Colors.orange,
            icone: Icons.info_outline,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SectionHeader garde son action visible', (tester) async {
      await tester.pumpWidget(_hote(
        SizedBox(
          width: 180,
          child: SectionHeader(
            titre: 'Ventes des sept derniers jours du magasin',
            icone: Icons.bar_chart_rounded,
            actionLabel: 'Voir tout',
            onAction: () {},
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Voir tout'), findsOneWidget);
    });

    testWidgets('AppButton tronque au lieu de déborder', (tester) async {
      await tester.pumpWidget(_hote(
        SizedBox(
          width: 120,
          child: AppButton(
            label: 'Enregistrer la vente et imprimer la facture',
            icon: Icons.check_rounded,
            expanded: true,
            onPressed: () {},
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('EtatVide', () {
    testWidgets('reste dans une carte étroite en mode compact',
        (tester) async {
      await tester.pumpWidget(_hote(
        const SizedBox(
          width: 200,
          height: 200,
          child: EtatVide(
            message: 'Aucun article en alerte',
            description: 'Tous les niveaux sont au-dessus du minimum.',
            icone: Icons.check_circle_outline_rounded,
            compact: true,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
