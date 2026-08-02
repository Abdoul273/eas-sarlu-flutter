import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'app_database.dart';

/// Clé utilisée pour la ligne unique de l'entreprise (enregistrement singleton).
const String kEntrepriseId = 'singleton';

/// Clé de la version de données locale dans la table Kv.
const String _kDataVersionKey = 'dataVersion';

/// Accès unifié aux données métier, stockées en JSON dans la table `records`
/// (clé composite `kind` + `id`).
///
/// Toutes les méthodes `watch*` renvoient un flux qui se met à jour
/// automatiquement à chaque écriture locale ou synchronisation.
class Stores {
  final AppDatabase _db;

  Stores(this._db);

  // --- Helpers internes ---

  /// Extrait l'identifiant d'un modèle selon son type.
  /// L'entreprise est un singleton et n'a pas de champ `id`.
  static String _idOf(String kind, dynamic model) {
    if (kind == 'entreprise') return kEntrepriseId;
    final id = model.id as String;
    if (id.isEmpty) {
      throw ArgumentError('Identifiant vide pour un enregistrement "$kind"');
    }
    return id;
  }

  /// Sélection de tous les enregistrements d'un type donné.
  SimpleSelectStatement<$RecordsTable, Record> _selectKind(String kind) {
    return _db.select(_db.records)..where((r) => r.kind.equals(kind));
  }

  /// Sélection d'un enregistrement précis.
  SimpleSelectStatement<$RecordsTable, Record> _selectOne(
      String kind, String id) {
    return _db.select(_db.records)
      ..where((r) => r.kind.equals(kind) & r.id.equals(id))
      ..limit(1);
  }

  static Map<String, dynamic> _decode(Record row) =>
      jsonDecode(row.json) as Map<String, dynamic>;

  /// Décode une liste de lignes puis trie avec [compare] si fourni.
  static List<T> _mapRows<T>(
    List<Record> rows,
    T Function(Map<String, dynamic>) fromJson, {
    int Function(T a, T b)? compare,
  }) {
    final items = rows.map((r) => fromJson(_decode(r))).toList();
    if (compare != null) items.sort(compare);
    return items;
  }

  // --- Écriture ---

  /// Insère ou met à jour un enregistrement métier.
  ///
  /// [kind] : 'article', 'vente', 'client', 'facture', 'depense',
  /// 'mouvement', 'entreprise' ou 'user'.
  Future<void> upsert(String kind, dynamic model) async {
    final json = model.toJson() as Map<String, dynamic>;
    await _db.into(_db.records).insertOnConflictUpdate(
          RecordsCompanion.insert(
            kind: kind,
            id: _idOf(kind, model),
            json: jsonEncode(json),
            rev: Value(json['_rev'] as int?),
            updatedAt: Value(json['_updatedAt'] as String?),
          ),
        );
  }

  /// Remplace l'intégralité des enregistrements d'un type (utilisé par le pull
  /// complet de synchronisation). Supprime puis réinsère dans une transaction
  /// afin qu'aucun état intermédiaire vide ne soit observé par l'UI.
  Future<void> remplacerTout(String kind, List<dynamic> models) async {
    await _db.transaction(() async {
      await (_db.delete(_db.records)..where((r) => r.kind.equals(kind))).go();
      for (final model in models) {
        final json = model.toJson() as Map<String, dynamic>;
        await _db.into(_db.records).insert(
              RecordsCompanion.insert(
                kind: kind,
                id: _idOf(kind, model),
                json: jsonEncode(json),
                rev: Value(json['_rev'] as int?),
                updatedAt: Value(json['_updatedAt'] as String?),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
    });
  }

  /// Applique l'instantané complet du serveur, en une seule transaction et par
  /// différence.
  ///
  /// Remplace `remplacerTout` appelé type par type, qui posait deux problèmes.
  ///
  /// D'abord le coût : effacer puis réinsérer toutes les lignes, c'est deux
  /// écritures par enregistrement à chaque synchronisation. Sur un catalogue de
  /// deux mille articles, la manœuvre se répétait à chaque vente — c'est de là
  /// que venaient les à-coups de l'application. Ici, seules les lignes dont la
  /// révision a changé sont réécrites ; une synchronisation qui n'apporte rien
  /// n'écrit rien.
  ///
  /// Ensuite la cohérence : chaque type avait sa propre transaction, si bien
  /// que l'écran pouvait observer les articles déjà remplacés et les ventes pas
  /// encore. Tout passe désormais dans une transaction unique.
  ///
  /// [parType] associe un `kind` à la liste complète des modèles renvoyés par
  /// le serveur pour ce type. Un type absent de la table n'est pas touché.
  Future<void> appliquerInstantane(Map<String, List<dynamic>> parType) async {
    await _db.transaction(() async {
      for (final entree in parType.entries) {
        final kind = entree.key;
        final modeles = entree.value;

        final existants = {
          for (final row in await _selectKind(kind).get()) row.id: row,
        };
        final vus = <String>{};

        for (final model in modeles) {
          final json = model.toJson() as Map<String, dynamic>;
          final id = _idOf(kind, model);
          vus.add(id);

          final encode = jsonEncode(json);
          final actuel = existants[id];
          // Comparer le JSON complet plutôt que la seule révision : le serveur
          // ne renseigne pas `_rev` sur tous les types, et une ligne dont rien
          // n'a bougé ne doit pas déclencher d'écriture — chaque écriture
          // réveille tous les flux qui observent ce type.
          if (actuel != null && actuel.json == encode) continue;

          await _db.into(_db.records).insert(
                RecordsCompanion.insert(
                  kind: kind,
                  id: id,
                  json: encode,
                  rev: Value(json['_rev'] as int?),
                  updatedAt: Value(json['_updatedAt'] as String?),
                ),
                mode: InsertMode.insertOrReplace,
              );
        }

        // Ce que le serveur ne renvoie plus a été supprimé chez lui.
        for (final id in existants.keys) {
          if (vus.contains(id)) continue;
          await (_db.delete(_db.records)
                ..where((r) => r.kind.equals(kind) & r.id.equals(id)))
              .go();
        }
      }
    });
  }

  /// Supprime un enregistrement quelconque.
  Future<void> supprimer(String kind, String id) async {
    await (_db.delete(_db.records)
          ..where((r) => r.kind.equals(kind) & r.id.equals(id)))
        .go();
  }

  Future<void> supprimerArticle(String id) => supprimer('article', id);

  Future<void> supprimerDepense(String id) => supprimer('depense', id);

  // --- Lecture ponctuelle ---

  Future<T?> _getOne<T>(
    String kind,
    String id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final row = await _selectOne(kind, id).getSingleOrNull();
    if (row == null) return null;
    return fromJson(_decode(row));
  }

  Future<Article?> getArticle(String id) =>
      _getOne('article', id, Article.fromJson);

  Future<Client?> getClient(String id) =>
      _getOne('client', id, Client.fromJson);

  Future<Vente?> getVente(String id) => _getOne('vente', id, Vente.fromJson);

  Future<Facture?> getFacture(String id) =>
      _getOne('facture', id, Facture.fromJson);

  Future<Depense?> getDepense(String id) =>
      _getOne('depense', id, Depense.fromJson);

  Future<MouvementStock?> getMouvement(String id) =>
      _getOne('mouvement', id, MouvementStock.fromJson);

  Future<Utilisateur?> getUtilisateur(String id) =>
      _getOne('user', id, Utilisateur.fromJson);

  /// L'entreprise est un enregistrement unique.
  Future<Entreprise?> getEntreprise() =>
      _getOne('entreprise', kEntrepriseId, Entreprise.fromJson);

  Future<List<Article>> getArticles() async {
    final rows = await _selectKind('article').get();
    return _mapRows(rows, Article.fromJson,
        compare: (a, b) => a.nom.compareTo(b.nom));
  }

  /// Lecture ponctuelle d'une collection entière.
  ///
  /// Doublon délibéré des flux `watch…` ci-dessous : un appelant qui ne veut
  /// qu'une photo (l'assistant qui construit son contexte, un test, un export)
  /// n'a pas à ouvrir un flux pour en prendre le premier élément. Ouvrir un flux
  /// pour le refermer aussitôt laisse une souscription à annuler, ce qui bloque
  /// la fermeture de la base dans les tests widget — et, en production, fait
  /// travailler drift pour rien.
  Future<List<T>> _getAll<T>(
    String kind,
    T Function(Map<String, dynamic>) fromJson, {
    int Function(T, T)? compare,
  }) async {
    final rows = await _selectKind(kind).get();
    return _mapRows(rows, fromJson, compare: compare);
  }

  /// Clients triés par nom.
  Future<List<Client>> getClients() => _getAll('client', Client.fromJson,
      compare: (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));

  /// Ventes, les plus récentes en premier.
  Future<List<Vente>> getVentes() => _getAll('vente', Vente.fromJson,
      compare: (a, b) => b.date.compareTo(a.date));

  /// Factures, les plus récentes en premier.
  Future<List<Facture>> getFactures() => _getAll('facture', Facture.fromJson,
      compare: (a, b) => b.dateEmission.compareTo(a.dateEmission));

  /// Dépenses, les plus récentes en premier.
  Future<List<Depense>> getDepenses() => _getAll('depense', Depense.fromJson,
      compare: (a, b) => b.date.compareTo(a.date));

  /// Mouvements de stock, les plus récents en premier.
  Future<List<MouvementStock>> getMouvements() =>
      _getAll('mouvement', MouvementStock.fromJson,
          compare: (a, b) => b.date.compareTo(a.date));

  /// Utilisateurs triés par nom.
  Future<List<Utilisateur>> getUtilisateurs() =>
      _getAll('user', Utilisateur.fromJson,
          compare: (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));

  // --- Flux réactifs ---

  /// Articles triés par nom.
  Stream<List<Article>> watchArticles() {
    return _selectKind('article').watch().map((rows) => _mapRows(
          rows,
          Article.fromJson,
          compare: (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()),
        ));
  }

  Stream<Article?> watchArticle(String id) {
    return _selectOne('article', id)
        .watchSingleOrNull()
        .map((row) => row == null ? null : Article.fromJson(_decode(row)));
  }

  /// Clients triés par nom.
  Stream<List<Client>> watchClients() {
    return _selectKind('client').watch().map((rows) => _mapRows(
          rows,
          Client.fromJson,
          compare: (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()),
        ));
  }

  /// Ventes, les plus récentes en premier.
  Stream<List<Vente>> watchVentes() {
    return _selectKind('vente').watch().map((rows) => _mapRows(
          rows,
          Vente.fromJson,
          compare: (a, b) => b.date.compareTo(a.date),
        ));
  }

  /// Factures, les plus récentes en premier.
  Stream<List<Facture>> watchFactures() {
    return _selectKind('facture').watch().map((rows) => _mapRows(
          rows,
          Facture.fromJson,
          compare: (a, b) => b.dateEmission.compareTo(a.dateEmission),
        ));
  }

  /// Dépenses, les plus récentes en premier.
  Stream<List<Depense>> watchDepenses() {
    return _selectKind('depense').watch().map((rows) => _mapRows(
          rows,
          Depense.fromJson,
          compare: (a, b) => b.date.compareTo(a.date),
        ));
  }

  /// Tous les mouvements de stock, les plus récents en premier.
  Stream<List<MouvementStock>> watchMouvements() {
    return _selectKind('mouvement').watch().map((rows) => _mapRows(
          rows,
          MouvementStock.fromJson,
          compare: (a, b) => b.date.compareTo(a.date),
        ));
  }

  /// Mouvements d'un article donné, les plus récents en premier.
  Stream<List<MouvementStock>> watchMouvementsByArticle(String articleId) {
    return watchMouvements().map(
        (mouvements) => mouvements.where((m) => m.articleId == articleId).toList());
  }

  /// Utilisateurs triés par nom.
  Stream<List<Utilisateur>> watchUtilisateurs() {
    return _selectKind('user').watch().map((rows) => _mapRows(
          rows,
          Utilisateur.fromJson,
          compare: (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()),
        ));
  }

  Stream<Entreprise?> watchEntreprise() {
    return _selectOne('entreprise', kEntrepriseId)
        .watchSingleOrNull()
        .map((row) => row == null ? null : Entreprise.fromJson(_decode(row)));
  }

  // --- Version de données (synchronisation) ---

  /// Version des données locales, `null` si aucun pull n'a encore eu lieu.
  Future<int?> getDataVersion() async {
    final row = await (_db.select(_db.kv)
          ..where((k) => k.cle.equals(_kDataVersionKey))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return int.tryParse(row.valeur);
  }

  Future<void> setDataVersion(int version) async {
    await _db.into(_db.kv).insertOnConflictUpdate(
          KvCompanion.insert(cle: _kDataVersionKey, valeur: '$version'),
        );
  }

  /// Vide toutes les données métier (déconnexion / changement de compte).
  Future<void> viderTout() async {
    await _db.transaction(() async {
      await _db.delete(_db.records).go();
      await (_db.delete(_db.kv)..where((k) => k.cle.equals(_kDataVersionKey)))
          .go();
    });
  }
}

final storesProvider = Provider<Stores>((ref) {
  return Stores(ref.watch(appDatabaseProvider));
});
