import 'package:eas_sarlu/core/db/app_database.dart';
import 'package:eas_sarlu/core/db/stores.dart';
import 'package:eas_sarlu/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vérifie la persistance locale : la table `records` stocke les modèles en
/// JSON et les flux `watch*` doivent refléter les écritures immédiatement.
void main() {
  late AppDatabase db;
  late Stores stores;

  setUp(() {
    db = AppDatabase.inMemory();
    stores = Stores(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert puis relecture conserve tous les champs', () async {
    final article = Article(
      id: 'a1',
      ref: 'TC-001',
      nom: 'Tube carré 40x40',
      categorie: 'Tube carré',
      unite: 'Barre',
      prixAchat: 120000,
      prixVente: 150000,
      stock: 50,
      stockMin: 10,
      longueur: 6.0,
      provenance: 'Turquie',
      rev: 3,
    );
    await stores.upsert('article', article);

    final relu = await stores.getArticle('a1');
    expect(relu, isNotNull);
    expect(relu!.nom, 'Tube carré 40x40');
    expect(relu.prixAchat, 120000);
    expect(relu.longueur, 6.0);
    expect(relu.provenance, 'Turquie');
    expect(relu.rev, 3);
  });

  test('upsert sur un id existant met à jour au lieu de dupliquer', () async {
    await stores.upsert('article',
        Article(id: 'a1', nom: 'Ancien nom', unite: 'Barre', stock: 5));
    await stores.upsert('article',
        Article(id: 'a1', nom: 'Nouveau nom', unite: 'Barre', stock: 8));

    final articles = await stores.getArticles();
    expect(articles.length, 1);
    expect(articles.first.nom, 'Nouveau nom');
    expect(articles.first.stock, 8);
  });

  test('l\'entreprise est un enregistrement unique', () async {
    await stores.upsert('entreprise', Entreprise(nom: 'E.A.S Sarlu'));
    await stores.upsert('entreprise', Entreprise(nom: 'E.A.S Sarlu v2'));

    final entreprise = await stores.getEntreprise();
    expect(entreprise, isNotNull);
    expect(entreprise!.nom, 'E.A.S Sarlu v2');
  });

  test('remplacerTout supprime les enregistrements absents du serveur',
      () async {
    await stores.upsert('client', Client(id: 'c1', nom: 'Ancien client'));
    await stores.upsert('client', Client(id: 'c2', nom: 'Client gardé'));

    await stores.remplacerTout('client', [
      Client(id: 'c2', nom: 'Client gardé'),
      Client(id: 'c3', nom: 'Nouveau client'),
    ]);

    expect(await stores.getClient('c1'), isNull);
    expect((await stores.getClient('c2'))?.nom, 'Client gardé');
    expect((await stores.getClient('c3'))?.nom, 'Nouveau client');
  });

  test('watchArticles trie par nom et suit les écritures', () async {
    expect(await stores.watchArticles().first, isEmpty);

    await stores.upsert(
        'article', Article(id: 'a1', nom: 'Zinc', unite: 'Feuille'));
    await stores.upsert(
        'article', Article(id: 'a2', nom: 'Acier', unite: 'Barre'));

    final articles = await stores.watchArticles().first;
    expect(articles.map((a) => a.nom), ['Acier', 'Zinc']);
  });

  test('watchMouvementsByArticle ne renvoie que l\'article visé', () async {
    await stores.upsert(
        'mouvement',
        MouvementStock(
            id: 'm1',
            articleId: 'a1',
            type: 'entrée',
            quantite: 10,
            date: '2026-07-01T10:00:00Z'));
    await stores.upsert(
        'mouvement',
        MouvementStock(
            id: 'm2',
            articleId: 'a2',
            type: 'sortie',
            quantite: 2,
            date: '2026-07-02T10:00:00Z'));
    await stores.upsert(
        'mouvement',
        MouvementStock(
            id: 'm3',
            articleId: 'a1',
            type: 'sortie',
            quantite: 3,
            date: '2026-07-03T10:00:00Z'));

    final mouvements = await stores.watchMouvementsByArticle('a1').first;
    expect(mouvements.length, 2);
    // Les plus récents d'abord.
    expect(mouvements.map((m) => m.id), ['m3', 'm1']);
  });

  test('la version de données est absente avant le premier pull', () async {
    expect(await stores.getDataVersion(), isNull);
    await stores.setDataVersion(42);
    expect(await stores.getDataVersion(), 42);
    await stores.setDataVersion(43);
    expect(await stores.getDataVersion(), 43);
  });

  test('viderTout efface données et version', () async {
    await stores.upsert('client', Client(id: 'c1', nom: 'Client'));
    await stores.setDataVersion(7);

    await stores.viderTout();

    expect(await stores.getClient('c1'), isNull);
    expect(await stores.getDataVersion(), isNull);
  });
}
