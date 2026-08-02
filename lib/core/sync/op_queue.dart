import 'dart:convert';
import 'dart:math' as math;
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';

// ─── File d'attente hors ligne ────────────────────────────────────────────────
// Conakry coupe souvent : toute opération faite sans réseau est déposée ici et
// rejouée au retour de la connexion.
//
// Deux propriétés portent tout le mode hors ligne :
//
// 1. `id` est un identifiant d'opération unique, généré ici. Le serveur le
//    mémorise après traitement : si la synchronisation part deux fois (réseau
//    instable, application rouverte), l'opération n'est appliquée qu'une seule
//    fois. C'est ce qui empêche les ventes et les factures en double.
//
// 2. Les opérations ne transportent jamais une collection entière ni un stock
//    recalculé, seulement l'enregistrement concerné et des écarts de stock.
//    Deux personnes qui travaillent hors ligne en parallèle ne s'écrasent donc
//    pas : leurs écarts se cumulent à la synchronisation.

/// Nombre de tentatives au-delà duquel une opération cesse de repartir seule.
///
/// Une opération que le serveur refuse toujours — un mouvement sur un article
/// supprimé entre-temps — repartait sans fin, à chaque cycle, et emportait avec
/// elle dans la même requête toutes les ventes légitimes de la file.
const int kMaxTentatives = 8;

/// Temporisation entre deux tentatives : 5 s, 10 s, 20 s… plafonnée à 5 min.
Duration _attenteApres(int tentatives) {
  final secondes = 5 * math.pow(2, (tentatives - 1).clamp(0, 6)).toInt();
  return Duration(seconds: math.min(secondes, 300));
}

class OpQueue {
  final AppDatabase _db;
  final _uuid = const Uuid();

  OpQueue(this._db);

  Future<String> enqueue(String type, Map<String, dynamic> payload,
      {String? libelle}) async {
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _db.into(_db.opQueue).insert(
          OpQueueCompanion(
            id: Value(id),
            type: Value(type),
            timestamp: Value(now),
            payloadJson: Value(jsonEncode(payload)),
            tentatives: const Value(0),
            creeLe: Value(now),
            libelle: Value(libelle),
          ),
        );
    return id;
  }

  /// Opérations prêtes à partir : ni bloquées, ni en temporisation.
  ///
  /// L'ordre de création est conservé — une vente doit atteindre le serveur
  /// avant le versement qui s'y rapporte.
  Future<List<OpQueueData>> getPendingOperations() async {
    final maintenant = DateTime.now().toIso8601String();
    return (_db.select(_db.opQueue)
          ..where((o) =>
              o.bloquee.equals(false) &
              (o.prochainEssai.isNull() |
                  o.prochainEssai.isSmallerOrEqualValue(maintenant)))
          ..orderBy([(t) => OrderingTerm(expression: t.creeLe)]))
        .get();
  }

  /// Toutes les opérations encore en base, temporisées et bloquées comprises.
  /// C'est ce que doit montrer l'indicateur de synchronisation : une opération
  /// bloquée reste du travail non parti.
  Future<List<OpQueueData>> getAllOperations() {
    return (_db.select(_db.opQueue)
          ..orderBy([(t) => OrderingTerm(expression: t.creeLe)]))
        .get();
  }

  Stream<int> watchPendingCount() {
    return _db.select(_db.opQueue).watch().map((rows) => rows.length);
  }

  /// Opérations définitivement arrêtées, à soumettre à l'utilisateur.
  Stream<List<OpQueueData>> watchBloquees() {
    return (_db.select(_db.opQueue)..where((o) => o.bloquee.equals(true)))
        .watch();
  }

  Stream<List<OpQueueData>> watchPendingOperations() {
    return (_db.select(_db.opQueue)
          ..orderBy([(t) => OrderingTerm(expression: t.creeLe)]))
        .watch();
  }

  /// L'opération a abouti : elle sort de la file.
  ///
  /// C'est une soustraction et non un remplacement. Une synchronisation dure le
  /// temps d'un aller-retour réseau, et le comptoir continue de travailler
  /// pendant ce temps : réécrire la file avec la liste calculée avant l'appel
  /// effacerait les ventes encaissées entre-temps.
  Future<void> markApplied(String id) async {
    await (_db.delete(_db.opQueue)..where((o) => o.id.equals(id))).go();
  }

  /// L'opération a échoué. Elle reste dans la file — un échec est le plus
  /// souvent transitoire (serveur indisponible, dépendance pas encore
  /// synchronisée) — mais elle attend avant de repartir, et finit par s'arrêter
  /// plutôt que de bloquer indéfiniment celles qui la suivent.
  Future<void> markFailed(String id, String error) async {
    final row = await (_db.select(_db.opQueue)
          ..where((o) => o.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return;

    final tentatives = row.tentatives + 1;
    final epuisee = tentatives >= kMaxTentatives;
    await (_db.update(_db.opQueue)..where((o) => o.id.equals(id))).write(
      OpQueueCompanion(
        tentatives: Value(tentatives),
        dernierErreur: Value(error),
        bloquee: Value(epuisee),
        prochainEssai: Value(epuisee
            ? null
            : DateTime.now().add(_attenteApres(tentatives)).toIso8601String()),
      ),
    );
  }

  /// Remet une opération bloquée en circulation, à la demande de l'utilisateur.
  Future<void> reprendre(String id) async {
    await (_db.update(_db.opQueue)..where((o) => o.id.equals(id))).write(
      const OpQueueCompanion(
        bloquee: Value(false),
        tentatives: Value(0),
        prochainEssai: Value(null),
      ),
    );
  }

  /// Abandonne une opération : l'utilisateur a vu le problème et renonce.
  Future<void> abandonner(String id) => markApplied(id);

  Future<void> updatePayload(String id, Map<String, dynamic> newPayload) async {
    await (_db.update(_db.opQueue)..where((o) => o.id.equals(id)))
        .write(OpQueueCompanion(payloadJson: Value(jsonEncode(newPayload))));
  }

  /// Vide la file. Réservé au changement de compte : les opérations en attente
  /// appartiennent à la session qui les a créées.
  Future<void> viderTout() async {
    await _db.delete(_db.opQueue).go();
  }
}

// ─── Conflits ─────────────────────────────────────────────────────────────────

class RegistreConflits {
  final AppDatabase _db;

  RegistreConflits(this._db);

  /// Dépose de nouveaux conflits sans toucher à ceux qui attendent déjà.
  ///
  /// `insertOrIgnore` : un conflit déjà soumis à l'utilisateur ne doit pas être
  /// réécrit par un second passage, sinon l'horodatage et la tentative
  /// conservée changeraient sous ses yeux.
  Future<void> ajouter(List<ConflitsCompanion> nouveaux) async {
    if (nouveaux.isEmpty) return;
    await _db.batch((b) {
      b.insertAll(_db.conflits, nouveaux, mode: InsertMode.insertOrIgnore);
    });
  }

  Stream<List<Conflit>> watch() => _db.select(_db.conflits).watch();

  Future<List<Conflit>> tous() => _db.select(_db.conflits).get();

  /// Retire un conflit une fois arbitré.
  Future<void> retirer(String id) async {
    await (_db.delete(_db.conflits)..where((c) => c.id.equals(id))).go();
  }

  Future<void> viderTout() async {
    await _db.delete(_db.conflits).go();
  }
}

final opQueueProvider = Provider<OpQueue>((ref) {
  return OpQueue(ref.watch(appDatabaseProvider));
});

final registreConflitsProvider = Provider<RegistreConflits>((ref) {
  return RegistreConflits(ref.watch(appDatabaseProvider));
});

final pendingOperationsProvider = StreamProvider<List<OpQueueData>>((ref) {
  return ref.watch(opQueueProvider).watchPendingOperations();
});

/// Opérations arrêtées, que l'utilisateur doit trancher.
final operationsBloqueesProvider = StreamProvider<List<OpQueueData>>((ref) {
  return ref.watch(opQueueProvider).watchBloquees();
});

final conflitsProvider = StreamProvider<List<Conflit>>((ref) {
  return ref.watch(registreConflitsProvider).watch();
});
