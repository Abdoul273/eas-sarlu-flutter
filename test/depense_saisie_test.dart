import 'package:eas_sarlu/app/format.dart';
import 'package:eas_sarlu/app/ui_kit.dart';
import 'package:eas_sarlu/core/db/app_database.dart' hide OpQueue;
import 'package:eas_sarlu/core/db/stores.dart';
import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/core/sync/op_queue.dart';
import 'package:eas_sarlu/features/depenses/depense_form_page.dart';
import 'package:eas_sarlu/features/depenses/reglement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  group('Saisie et parsing des montants de dépenses', () {
    test('parseMontantClean nettoie et extrait les entiers correctement', () {
      expect(parseMontantClean('100 000 GNF'), 100000);
      expect(parseMontantClean('50 000'), 50000);
      expect(parseMontantClean('1 500 000 GNF'), 1500000);
      expect(parseMontantClean('0'), 0);
      expect(parseMontantClean(''), 0);
      expect(parseMontantClean(null), 0);
    });

    testWidgets('ChampMontant n\'inclut pas GNF dans le controller et formate en milliers',
        (tester) async {
      final ctrl = TextEditingController(text: '100000');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChampMontant(
              controller: ctrl,
              labelText: 'Montant *',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Le texte affiché dans le controller contient les chiffres et séparateurs, mais PAS "GNF"
      expect(ctrl.text.replaceAll(RegExp(r'\s'), ''), '100000');
      expect(ctrl.text.contains('GNF'), isFalse);

      // Et le suffixe visuel GNF est présent dans l'arborescence
      expect(find.text('GNF'), findsOneWidget);
    });

    testWidgets('DepenseFormPage enregistre avec succès un montant saisi',
        (tester) async {
      final db = AppDatabase.inMemory();
      final stores = Stores(db);
      final opQueue = OpQueue(db);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storesProvider.overrideWithValue(stores),
            opQueueProvider.overrideWithValue(opQueue),
          ],
          child: const MaterialApp(
            home: DepenseFormPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Saisie du libellé
      final libelleFinder = find.widgetWithText(TextField, 'Libellé *');
      await tester.enterText(libelleFinder, 'Achat carburant');

      // Saisie du montant dans ChampMontant
      final montantFinder = find.widgetWithText(TextField, 'Montant *');
      await tester.enterText(montantFinder, '250000');
      await tester.pumpAndSettle();

      // Enregistrer
      final boutonEnregistrer = find.text('Enregistrer');
      await tester.ensureVisible(boutonEnregistrer);
      await tester.tap(boutonEnregistrer);
      await tester.pumpAndSettle();

      // Vérifier que la dépense est enregistrée dans le store avec le montant 250 000 GNF
      final depenses = await stores.watchDepenses().first;
      expect(depenses.length, 1);
      expect(depenses.first.libelle, 'Achat carburant');
      expect(depenses.first.montant, 250000);

      await db.close();
    });

    testWidgets('ReglementSheet enregistre avec succès un règlement',
        (tester) async {
      final db = AppDatabase.inMemory();
      final stores = Stores(db);
      final opQueue = OpQueue(db);

      final depense = Depense(
        id: 'dep1',
        numero: 'DEP-001',
        date: '2026-08-01',
        categorie: 'Divers',
        libelle: 'Transport',
        beneficiaire: 'Chauffeur',
        montant: 500000,
        reglements: [],
      );

      await stores.upsert('depense', depense);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storesProvider.overrideWithValue(stores),
            opQueueProvider.overrideWithValue(opQueue),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReglementSheet(depense: depense),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Par défaut, le champ du montant propose le reste (500 000)
      final validerBtn = find.text('Valider le règlement');
      await tester.tap(validerBtn);
      await tester.pumpAndSettle();

      final misAJour = await stores.getDepense('dep1');
      expect(misAJour, isNotNull);
      expect(misAJour!.reglements.length, 1);
      expect(misAJour.reglements.first.montant, 500000);
      expect(montantRegle(misAJour), 500000);
      expect(statutDepense(misAJour), 'réglée');

      await db.close();
    });
  });
}
