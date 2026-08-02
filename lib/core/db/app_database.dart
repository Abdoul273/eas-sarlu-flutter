import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

part 'app_database.g.dart';

class Records extends Table {
  TextColumn get kind => text()();
  TextColumn get id => text()();
  TextColumn get json => text()();
  IntColumn get rev => integer().nullable()();
  TextColumn get updatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {kind, id};
}

class OpQueue extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get timestamp => text()();
  TextColumn get payloadJson => text()();
  IntColumn get tentatives => integer().withDefault(const Constant(0))();
  TextColumn get dernierErreur => text().nullable()();
  TextColumn get creeLe => text()();

  /// Instant avant lequel l'opération ne doit pas repartir.
  ///
  /// Sans cette colonne, une opération que le serveur refuse toujours — un
  /// mouvement sur un article supprimé, par exemple — repartait à chaque cycle
  /// et emportait avec elle, dans la même requête, toutes les ventes légitimes
  /// de la file.
  TextColumn get prochainEssai => text().nullable()();

  /// L'opération a épuisé ses tentatives. Elle reste en base pour que
  /// l'utilisateur la voie et décide, mais ne repart plus d'elle-même.
  BoolColumn get bloquee => boolean().withDefault(const Constant(false))();

  /// Libellé lisible, repris de l'application web : « Vente VTE-2026-0377 ».
  /// Sans lui, un conflit s'annonce par un identifiant technique.
  TextColumn get libelle => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Conflits de synchronisation en attente d'arbitrage.
///
/// Une opération en conflit SORT de la file : la rejouer en boucle referait
/// échouer la synchronisation à chaque retour de réseau sans jamais rien
/// résoudre. Elle atterrit ici, où elle attend que l'utilisateur tranche —
/// rien n'est jeté sans qu'il l'ait vu. C'est la règle de l'application web
/// (`partitionnerFile`), et les deux doivent se comporter pareil.
class Conflits extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get libelle => text()();

  /// Ce que l'appareil a tenté d'écrire.
  TextColumn get tentativeJson => text()();

  /// Ce que le serveur a de son côté.
  TextColumn get serveurJson => text()();
  TextColumn get detecteLe => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Kv extends Table {
  TextColumn get cle => text()();
  TextColumn get valeur => text()();

  @override
  Set<Column> get primaryKey => {cle};
}

@DriftDatabase(tables: [Records, OpQueue, Kv, Conflits])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Constructeur pour les tests (base en mémoire)
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, depuis, vers) async {
          // La migration ne touche PAS à la table `records` ni à `opQueue` :
          // une mise à jour de l'application ne doit jamais faire disparaître
          // des ventes saisies hors ligne et pas encore parties.
          if (depuis < 2) {
            await m.addColumn(opQueue, opQueue.prochainEssai);
            await m.addColumn(opQueue, opQueue.bloquee);
            await m.addColumn(opQueue, opQueue.libelle);
            await m.createTable(conflits);
          }
        },
        beforeOpen: (details) async {
          // Les clés étrangères ne sont pas actives par défaut sous SQLite.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'eas_sarlu.db'));
    return NativeDatabase(file);
  });
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});
