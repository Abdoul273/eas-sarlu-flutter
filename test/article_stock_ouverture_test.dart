// Le stock de départ d'un article nouvellement créé.
//
// Jusqu'ici il était posé directement dans la fiche, sans aucune trace :
// l'historique de l'article restait vide alors qu'il y avait cinquante barres
// en dépôt, et plus personne ne pouvait dire d'où elles venaient.
//
// Trois propriétés portent tout l'écran, et chacune peut fausser le stock :
//
//   1. l'article naît à ZÉRO et c'est le mouvement qui pose la quantité. L'y
//      écrire AUSSI la compterait deux fois, le serveur appliquant le mouvement
//      par-dessus la fiche ;
//   2. l'article est déposé dans la file AVANT le mouvement — le serveur refuse
//      un mouvement sur un article qu'il ne connaît pas encore ;
//   3. une reprise d'inventaire n'est attribuée à personne, et une livraison
//      porte le nom de son fournisseur, recopié.

import 'package:eas_sarlu/core/db/app_database.dart' hide OpQueue;
import 'package:eas_sarlu/core/db/stores.dart';
import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/core/sync/op_queue.dart';
import 'package:eas_sarlu/core/sync/sync_engine.dart';
import 'package:eas_sarlu/core/sync/sync_state.dart';
import 'package:eas_sarlu/core/api/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends Fake implements FlutterSecureStorage {}

void main() {
  late AppDatabase db;
  late Stores stores;
  late OpQueue opQueue;

  setUp(() {
    db = AppDatabase.inMemory();
    stores = Stores(db);
    opQueue = OpQueue(db);
  });

  // La base n'est pas refermée : `close()` reste suspendu dans le temps simulé
  // d'un test, et chaque test reçoit de toute façon une base neuve en mémoire.

  SyncEngine moteur() => SyncEngine(
        apiClient: ApiClient(secureStorage: _FakeStorage()),
        stores: stores,
        opQueue: opQueue,
        conflits: RegistreConflits(db),
        syncState: SyncStateNotifier(opQueue.watchPendingCount()),
        connectivity: Connectivity(),
      );

  /// Reproduit ce que fait le formulaire d'article à l'enregistrement.
  Future<void> creerArticle({
    required int quantite,
    Fournisseur? fournisseur,
  }) async {
    final article = Article(
      id: 'a1',
      ref: 'FER8',
      nom: 'Fer à béton 8',
      categorie: 'Fer',
      unite: 'Barre',
      prixAchat: 60000,
      prixVente: 85000,
      // Zéro : c'est le mouvement qui posera la quantité.
      stock: 0,
      stockMin: 10,
      fournisseur: fournisseur?.nom ?? '',
    );
    await stores.upsert('article', article);
    await opQueue.enqueue('article', {'record': article.toJson()});

    if (quantite <= 0) return;

    final livraison = fournisseur != null;
    final mouvement = MouvementStock(
      id: 'mv1',
      articleId: article.id,
      type: livraison ? 'entrée' : 'ajustement',
      quantite: quantite,
      quantiteAvant: 0,
      quantiteApres: quantite,
      date: '2026-08-02T10:00:00.000Z',
      utilisateur: 'Abdoul',
      note: livraison
          ? 'Première livraison à la création de l\'article'
          : 'Stock déjà en magasin à la création de l\'article',
      fournisseurId: livraison ? fournisseur.id : null,
      fournisseurNom: livraison ? fournisseur.nom : null,
      fournisseurQuartier:
          livraison && fournisseur.quartier.isNotEmpty ? fournisseur.quartier : null,
    );
    await stores.upsert('mouvement', mouvement);
    await stores.upsert('article', article.copyWith(stock: quantite));
    await opQueue.enqueue('mouvement', {'mouvement': mouvement.toJson()});
  }

  group('Reprise d\'inventaire', () {
    test('pose le stock et le dit, sans l\'attribuer à personne', () async {
      await creerArticle(quantite: 50);

      expect((await stores.getArticle('a1'))?.stock, 50,
          reason: 'le stock doit être visible tout de suite, hors ligne');

      final m = (await stores.getMouvements()).single;
      expect(m.type, 'ajustement',
          reason: 'un solde d\'ouverture est un état constaté, pas une entrée');
      expect(m.quantite, 50);
      expect(m.fournisseurId, isNull,
          reason: 'attribuer une reprise à quelqu\'un inventerait un achat');
      expect(m.note, contains('Stock déjà en magasin'));
    });
  });

  group('Livraison fournisseur', () {
    final turquie = Fournisseur(
      id: 'fo1',
      nom: 'Import Turquie',
      telephone: '622000001',
      quartier: 'Matoto',
      creeLe: '2026-01-10',
    );

    test('rattache le stock au fournisseur, nom recopié', () async {
      await creerArticle(quantite: 50, fournisseur: turquie);

      final m = (await stores.getMouvements()).single;
      expect(m.type, 'entrée');
      expect(m.fournisseurId, 'fo1');
      // Le nom est recopié en plus de l'identifiant : un fournisseur renommé ou
      // supprimé ne doit pas effacer la trace de ce qui a été pris chez lui.
      expect(m.fournisseurNom, 'Import Turquie');
      expect(m.fournisseurQuartier, 'Matoto');
      expect((await stores.getArticle('a1'))?.stock, 50);
    });

    test('renseigne le fournisseur habituel de la fiche', () async {
      await creerArticle(quantite: 50, fournisseur: turquie);
      expect((await stores.getArticle('a1'))?.fournisseur, 'Import Turquie');
    });
  });

  group('Ce qui part au serveur', () {
    test('l\'article passe AVANT le mouvement dans la file', () async {
      await creerArticle(quantite: 50);

      final ops = await opQueue.getPendingOperations();
      expect(ops.map((o) => o.type).toList(), ['article', 'mouvement'],
          reason: 'le serveur refuse un mouvement sur un article inconnu');
    });

    test('la fiche envoyée porte un stock de zéro', () async {
      await creerArticle(quantite: 50, fournisseur: null);

      final opArticle = (await opQueue.getPendingOperations())
          .firstWhere((o) => o.type == 'article');
      expect(opArticle.payloadJson, contains('"stock":0'),
          reason: 'la quantité est portée par le mouvement ; l\'écrire aussi '
              'dans la fiche la compterait deux fois');
    });

    test('aucun mouvement quand le stock de départ est nul', () async {
      await creerArticle(quantite: 0);

      expect(await stores.getMouvements(), isEmpty);
      expect((await opQueue.getPendingOperations()).map((o) => o.type).toList(),
          ['article']);
    });
  });

  group('Après synchronisation', () {
    test('le rejeu ne compte pas la quantité une seconde fois', () async {
      // Le cas qui fait tout dérailler : l'instantané arrive avant que le
      // mouvement ne soit poussé. Le serveur rend l'article à zéro, et le rejeu
      // local doit reposer 50 — pas 100.
      final engine = moteur();
      await creerArticle(quantite: 50);

      await engine.debugAppliquerInstantane({
        'ventes': [], 'factures': [], 'clients': [], 'depenses': [],
        'mouvements': [],
        'articles': [
          {
            'id': 'a1',
            'nom': 'Fer à béton 8',
            'unite': 'Barre',
            'stock': 0,
            '_rev': 1,
          },
        ],
      });
      await engine.debugRejouerOperationsLocales();

      expect((await stores.getArticle('a1'))?.stock, 50);
    });

    test('une fois le serveur au courant, rien n\'est rejoué', () async {
      final engine = moteur();
      await creerArticle(quantite: 50);

      await engine.debugAppliquerInstantane({
        'ventes': [], 'factures': [], 'clients': [], 'depenses': [],
        'articles': [
          {
            'id': 'a1',
            'nom': 'Fer à béton 8',
            'unite': 'Barre',
            'stock': 50,
            '_rev': 2,
          },
        ],
        'mouvements': [
          {
            'id': 'mv1',
            'articleId': 'a1',
            'type': 'ajustement',
            'quantite': 50,
            'date': '2026-08-02T10:00:00.000Z',
          },
        ],
      });
      await engine.debugRejouerOperationsLocales();

      expect((await stores.getArticle('a1'))?.stock, 50,
          reason: 'le mouvement est déjà compris dans le stock du serveur');
    });
  });
}
