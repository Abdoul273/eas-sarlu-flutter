// Vérifie l'ajustement d'inventaire : le seul moyen de remettre un stock
// d'aplomb quand il ne correspond plus au dépôt.
//
// Deux propriétés portent tout l'écran :
//   — la quantité enregistrée est le stock VOULU, pas l'écart. C'est ainsi que
//     le serveur la lit, et une confusion ici ajouterait 500 barres au lieu de
//     ramener le stock à 500 ;
//   — l'écriture est locale AVANT l'envoi, sans quoi la correction ne se verrait
//     pas hors ligne et serait refaite.

import 'package:eas_sarlu/core/db/app_database.dart' hide OpQueue;
import 'package:eas_sarlu/core/db/stores.dart';
import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/core/sync/op_queue.dart';
import 'package:eas_sarlu/features/stock/ajustement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late AppDatabase db;
  late Stores stores;
  late OpQueue opQueue;

  setUpAll(() => initializeDateFormatting('fr_FR', null));

  setUp(() async {
    db = AppDatabase.inMemory();
    stores = Stores(db);
    opQueue = OpQueue(db);
  });

  // La base n'est PAS refermée ici. `db.close()` dans un `tearDown` reste
  // suspendu : le temps du test est simulé, et le nettoyage interne de drift
  // attend des minuteurs qui ne s'exécuteront plus une fois le test terminé —
  // le fichier entier partait alors en expiration au bout de dix minutes, sans
  // rien dire d'utile. Chaque test reçoit de toute façon une base neuve, en
  // mémoire, que la fin du processus emporte.

  Article article({int stock = 500}) => Article(
        id: 'a1',
        ref: 'FER8',
        nom: 'Fer à béton 8',
        categorie: 'Fer',
        unite: 'Barre',
        prixAchat: 60000,
        prixVente: 85000,
        stock: stock,
        stockMin: 20,
      );

  Future<void> monter(WidgetTester tester, Article a) async {
    await stores.upsert('article', a);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storesProvider.overrideWithValue(stores),
          opQueueProvider.overrideWithValue(opQueue),
        ],
        child: MaterialApp(home: Scaffold(body: AjustementSheet(article: a))),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Le bouton est en bas d'une feuille plus haute que l'écran de test : sans
  /// `ensureVisible`, l'appui tombe à côté et ne déclenche rien — en silence.
  Future<void> enregistrer(WidgetTester tester) async {
    final bouton = find.text("Enregistrer l'ajustement");
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
  }

  /// Vide le bandeau d'avertissement avant la fin du test.
  ///
  /// Il se referme seul au bout de quelques secondes ; laisser son minuteur en
  /// vol empêche la base de se refermer dans `tearDown`, et le test entier part
  /// en expiration sans rien dire d'utile.
  Future<void> purgerBandeau(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> saisirCompte(WidgetTester tester, String valeur) async {
    await tester.enterText(
        find.widgetWithText(TextField, "Ce qu'il y a en dépôt"), valeur);
    await tester.pumpAndSettle();
  }

  testWidgets('part du stock enregistré : ne rien toucher ne change rien',
      (tester) async {
    await monter(tester, article(stock: 500));

    expect(find.text('aucun'), findsOneWidget);

    await enregistrer(tester);
    await tester.pump();

    // Ni mouvement, ni opération : un ajustement qui ne corrige rien encombre
    // le journal et fait croire à une correction qui n'a pas eu lieu.
    expect(await stores.getMouvements(), isEmpty);
    expect(await opQueue.getAllOperations(), isEmpty);
    expect(find.textContaining('déjà celui enregistré'), findsOneWidget);
    await purgerBandeau(tester);
  });

  testWidgets('exige un motif avant toute correction', (tester) async {
    await monter(tester, article(stock: 500));
    await saisirCompte(tester, '50');

    await enregistrer(tester);
    await tester.pump();

    expect(await stores.getMouvements(), isEmpty,
        reason: 'un ajustement sans motif ne doit rien écrire');
    expect(await opQueue.getAllOperations(), isEmpty);
    expect(find.textContaining('pourquoi le stock est corrigé'), findsOneWidget);
    await purgerBandeau(tester);
  });

  testWidgets('corrige 500 en 50 : le stock devient 50, et non 550',
      (tester) async {
    // La faute classique : lire la quantité d'un ajustement comme un écart.
    // Le serveur l'applique en mode « absolu » ; l'écran doit dire pareil.
    await monter(tester, article(stock: 500));
    await saisirCompte(tester, '50');
    await tester.tap(find.text('Erreur de saisie'));
    await tester.pumpAndSettle();

    expect(find.text('−450 Barre'), findsOneWidget);

    await enregistrer(tester);
    await tester.pumpAndSettle();

    // Le stock est corrigé LOCALEMENT, sans attendre le réseau.
    expect((await stores.getArticle('a1'))?.stock, 50);

    final mouvements = await stores.getMouvements();
    expect(mouvements, hasLength(1));
    final m = mouvements.single;
    expect(m.type, 'ajustement');
    expect(m.quantite, 50, reason: 'la quantité est le stock voulu, pas l\'écart');
    expect(m.quantiteAvant, 500);
    expect(m.quantiteApres, 50);
    expect(m.note, contains('Erreur de saisie'));

    // Et l'opération part bien dans la file.
    final ops = await opQueue.getAllOperations();
    expect(ops, hasLength(1));
    expect(ops.single.type, 'mouvement');
  });

  testWidgets('un comptage supérieur remonte le stock', (tester) async {
    await monter(tester, article(stock: 10));
    await saisirCompte(tester, '42');
    await tester.tap(find.text('Comptage / inventaire'));
    await tester.pumpAndSettle();

    expect(find.text('+32 Barre'), findsOneWidget);

    await enregistrer(tester);
    await tester.pumpAndSettle();

    expect((await stores.getArticle('a1'))?.stock, 42);
  });

  testWidgets('la précision libre complète le motif sans le remplacer',
      (tester) async {
    await monter(tester, article(stock: 10));
    await saisirCompte(tester, '4');
    await tester.tap(find.text('Casse ou détérioration'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Précision (optionnel)'),
        'Chute du camion au déchargement');
    await tester.pumpAndSettle();

    await enregistrer(tester);
    await tester.pumpAndSettle();

    final m = (await stores.getMouvements()).single;
    expect(m.note, 'Casse ou détérioration — Chute du camion au déchargement');
  });

  testWidgets('ramener un stock à zéro reste possible', (tester) async {
    // `parseMontantClean('')` vaut zéro : un champ vidé ne doit pas être pris
    // pour « pas de saisie », sinon on ne peut plus solder un article.
    await monter(tester, article(stock: 7));
    await saisirCompte(tester, '0');
    await tester.tap(find.text('Perte ou vol'));
    await tester.pumpAndSettle();

    await enregistrer(tester);
    await tester.pumpAndSettle();

    expect((await stores.getArticle('a1'))?.stock, 0);
    expect((await stores.getMouvements()).single.quantite, 0);
  });
}
