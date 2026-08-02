// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $RecordsTable extends Records with TableInfo<$RecordsTable, Record> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
      'rev', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [kind, id, json, rev, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'records';
  @override
  VerificationContext validateIntegrity(Insertable<Record> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
          _revMeta, rev.isAcceptableOrUnknown(data['rev']!, _revMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, id};
  @override
  Record map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Record(
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
      rev: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rev']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $RecordsTable createAlias(String alias) {
    return $RecordsTable(attachedDatabase, alias);
  }
}

class Record extends DataClass implements Insertable<Record> {
  final String kind;
  final String id;
  final String json;
  final int? rev;
  final String? updatedAt;
  const Record(
      {required this.kind,
      required this.id,
      required this.json,
      this.rev,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['id'] = Variable<String>(id);
    map['json'] = Variable<String>(json);
    if (!nullToAbsent || rev != null) {
      map['rev'] = Variable<int>(rev);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    return map;
  }

  RecordsCompanion toCompanion(bool nullToAbsent) {
    return RecordsCompanion(
      kind: Value(kind),
      id: Value(id),
      json: Value(json),
      rev: rev == null && nullToAbsent ? const Value.absent() : Value(rev),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Record.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Record(
      kind: serializer.fromJson<String>(json['kind']),
      id: serializer.fromJson<String>(json['id']),
      json: serializer.fromJson<String>(json['json']),
      rev: serializer.fromJson<int?>(json['rev']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'id': serializer.toJson<String>(id),
      'json': serializer.toJson<String>(json),
      'rev': serializer.toJson<int?>(rev),
      'updatedAt': serializer.toJson<String?>(updatedAt),
    };
  }

  Record copyWith(
          {String? kind,
          String? id,
          String? json,
          Value<int?> rev = const Value.absent(),
          Value<String?> updatedAt = const Value.absent()}) =>
      Record(
        kind: kind ?? this.kind,
        id: id ?? this.id,
        json: json ?? this.json,
        rev: rev.present ? rev.value : this.rev,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  Record copyWithCompanion(RecordsCompanion data) {
    return Record(
      kind: data.kind.present ? data.kind.value : this.kind,
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
      rev: data.rev.present ? data.rev.value : this.rev,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Record(')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('rev: $rev, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, id, json, rev, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Record &&
          other.kind == this.kind &&
          other.id == this.id &&
          other.json == this.json &&
          other.rev == this.rev &&
          other.updatedAt == this.updatedAt);
}

class RecordsCompanion extends UpdateCompanion<Record> {
  final Value<String> kind;
  final Value<String> id;
  final Value<String> json;
  final Value<int?> rev;
  final Value<String?> updatedAt;
  final Value<int> rowid;
  const RecordsCompanion({
    this.kind = const Value.absent(),
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.rev = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordsCompanion.insert({
    required String kind,
    required String id,
    required String json,
    this.rev = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : kind = Value(kind),
        id = Value(id),
        json = Value(json);
  static Insertable<Record> custom({
    Expression<String>? kind,
    Expression<String>? id,
    Expression<String>? json,
    Expression<int>? rev,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (rev != null) 'rev': rev,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordsCompanion copyWith(
      {Value<String>? kind,
      Value<String>? id,
      Value<String>? json,
      Value<int?>? rev,
      Value<String?>? updatedAt,
      Value<int>? rowid}) {
    return RecordsCompanion(
      kind: kind ?? this.kind,
      id: id ?? this.id,
      json: json ?? this.json,
      rev: rev ?? this.rev,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordsCompanion(')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('rev: $rev, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OpQueueTable extends OpQueue with TableInfo<$OpQueueTable, OpQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OpQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<String> timestamp = GeneratedColumn<String>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tentativesMeta =
      const VerificationMeta('tentatives');
  @override
  late final GeneratedColumn<int> tentatives = GeneratedColumn<int>(
      'tentatives', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _dernierErreurMeta =
      const VerificationMeta('dernierErreur');
  @override
  late final GeneratedColumn<String> dernierErreur = GeneratedColumn<String>(
      'dernier_erreur', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _creeLeMeta = const VerificationMeta('creeLe');
  @override
  late final GeneratedColumn<String> creeLe = GeneratedColumn<String>(
      'cree_le', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _prochainEssaiMeta =
      const VerificationMeta('prochainEssai');
  @override
  late final GeneratedColumn<String> prochainEssai = GeneratedColumn<String>(
      'prochain_essai', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _bloqueeMeta =
      const VerificationMeta('bloquee');
  @override
  late final GeneratedColumn<bool> bloquee = GeneratedColumn<bool>(
      'bloquee', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("bloquee" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _libelleMeta =
      const VerificationMeta('libelle');
  @override
  late final GeneratedColumn<String> libelle = GeneratedColumn<String>(
      'libelle', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        timestamp,
        payloadJson,
        tentatives,
        dernierErreur,
        creeLe,
        prochainEssai,
        bloquee,
        libelle
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'op_queue';
  @override
  VerificationContext validateIntegrity(Insertable<OpQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('tentatives')) {
      context.handle(
          _tentativesMeta,
          tentatives.isAcceptableOrUnknown(
              data['tentatives']!, _tentativesMeta));
    }
    if (data.containsKey('dernier_erreur')) {
      context.handle(
          _dernierErreurMeta,
          dernierErreur.isAcceptableOrUnknown(
              data['dernier_erreur']!, _dernierErreurMeta));
    }
    if (data.containsKey('cree_le')) {
      context.handle(_creeLeMeta,
          creeLe.isAcceptableOrUnknown(data['cree_le']!, _creeLeMeta));
    } else if (isInserting) {
      context.missing(_creeLeMeta);
    }
    if (data.containsKey('prochain_essai')) {
      context.handle(
          _prochainEssaiMeta,
          prochainEssai.isAcceptableOrUnknown(
              data['prochain_essai']!, _prochainEssaiMeta));
    }
    if (data.containsKey('bloquee')) {
      context.handle(_bloqueeMeta,
          bloquee.isAcceptableOrUnknown(data['bloquee']!, _bloqueeMeta));
    }
    if (data.containsKey('libelle')) {
      context.handle(_libelleMeta,
          libelle.isAcceptableOrUnknown(data['libelle']!, _libelleMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OpQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OpQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}timestamp'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      tentatives: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tentatives'])!,
      dernierErreur: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}dernier_erreur']),
      creeLe: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cree_le'])!,
      prochainEssai: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prochain_essai']),
      bloquee: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}bloquee'])!,
      libelle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}libelle']),
    );
  }

  @override
  $OpQueueTable createAlias(String alias) {
    return $OpQueueTable(attachedDatabase, alias);
  }
}

class OpQueueData extends DataClass implements Insertable<OpQueueData> {
  final String id;
  final String type;
  final String timestamp;
  final String payloadJson;
  final int tentatives;
  final String? dernierErreur;
  final String creeLe;

  /// Instant avant lequel l'opération ne doit pas repartir.
  ///
  /// Sans cette colonne, une opération que le serveur refuse toujours — un
  /// mouvement sur un article supprimé, par exemple — repartait à chaque cycle
  /// et emportait avec elle, dans la même requête, toutes les ventes légitimes
  /// de la file.
  final String? prochainEssai;

  /// L'opération a épuisé ses tentatives. Elle reste en base pour que
  /// l'utilisateur la voie et décide, mais ne repart plus d'elle-même.
  final bool bloquee;

  /// Libellé lisible, repris de l'application web : « Vente VTE-2026-0377 ».
  /// Sans lui, un conflit s'annonce par un identifiant technique.
  final String? libelle;
  const OpQueueData(
      {required this.id,
      required this.type,
      required this.timestamp,
      required this.payloadJson,
      required this.tentatives,
      this.dernierErreur,
      required this.creeLe,
      this.prochainEssai,
      required this.bloquee,
      this.libelle});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['timestamp'] = Variable<String>(timestamp);
    map['payload_json'] = Variable<String>(payloadJson);
    map['tentatives'] = Variable<int>(tentatives);
    if (!nullToAbsent || dernierErreur != null) {
      map['dernier_erreur'] = Variable<String>(dernierErreur);
    }
    map['cree_le'] = Variable<String>(creeLe);
    if (!nullToAbsent || prochainEssai != null) {
      map['prochain_essai'] = Variable<String>(prochainEssai);
    }
    map['bloquee'] = Variable<bool>(bloquee);
    if (!nullToAbsent || libelle != null) {
      map['libelle'] = Variable<String>(libelle);
    }
    return map;
  }

  OpQueueCompanion toCompanion(bool nullToAbsent) {
    return OpQueueCompanion(
      id: Value(id),
      type: Value(type),
      timestamp: Value(timestamp),
      payloadJson: Value(payloadJson),
      tentatives: Value(tentatives),
      dernierErreur: dernierErreur == null && nullToAbsent
          ? const Value.absent()
          : Value(dernierErreur),
      creeLe: Value(creeLe),
      prochainEssai: prochainEssai == null && nullToAbsent
          ? const Value.absent()
          : Value(prochainEssai),
      bloquee: Value(bloquee),
      libelle: libelle == null && nullToAbsent
          ? const Value.absent()
          : Value(libelle),
    );
  }

  factory OpQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OpQueueData(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      timestamp: serializer.fromJson<String>(json['timestamp']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      tentatives: serializer.fromJson<int>(json['tentatives']),
      dernierErreur: serializer.fromJson<String?>(json['dernierErreur']),
      creeLe: serializer.fromJson<String>(json['creeLe']),
      prochainEssai: serializer.fromJson<String?>(json['prochainEssai']),
      bloquee: serializer.fromJson<bool>(json['bloquee']),
      libelle: serializer.fromJson<String?>(json['libelle']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'timestamp': serializer.toJson<String>(timestamp),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'tentatives': serializer.toJson<int>(tentatives),
      'dernierErreur': serializer.toJson<String?>(dernierErreur),
      'creeLe': serializer.toJson<String>(creeLe),
      'prochainEssai': serializer.toJson<String?>(prochainEssai),
      'bloquee': serializer.toJson<bool>(bloquee),
      'libelle': serializer.toJson<String?>(libelle),
    };
  }

  OpQueueData copyWith(
          {String? id,
          String? type,
          String? timestamp,
          String? payloadJson,
          int? tentatives,
          Value<String?> dernierErreur = const Value.absent(),
          String? creeLe,
          Value<String?> prochainEssai = const Value.absent(),
          bool? bloquee,
          Value<String?> libelle = const Value.absent()}) =>
      OpQueueData(
        id: id ?? this.id,
        type: type ?? this.type,
        timestamp: timestamp ?? this.timestamp,
        payloadJson: payloadJson ?? this.payloadJson,
        tentatives: tentatives ?? this.tentatives,
        dernierErreur:
            dernierErreur.present ? dernierErreur.value : this.dernierErreur,
        creeLe: creeLe ?? this.creeLe,
        prochainEssai:
            prochainEssai.present ? prochainEssai.value : this.prochainEssai,
        bloquee: bloquee ?? this.bloquee,
        libelle: libelle.present ? libelle.value : this.libelle,
      );
  OpQueueData copyWithCompanion(OpQueueCompanion data) {
    return OpQueueData(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      tentatives:
          data.tentatives.present ? data.tentatives.value : this.tentatives,
      dernierErreur: data.dernierErreur.present
          ? data.dernierErreur.value
          : this.dernierErreur,
      creeLe: data.creeLe.present ? data.creeLe.value : this.creeLe,
      prochainEssai: data.prochainEssai.present
          ? data.prochainEssai.value
          : this.prochainEssai,
      bloquee: data.bloquee.present ? data.bloquee.value : this.bloquee,
      libelle: data.libelle.present ? data.libelle.value : this.libelle,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OpQueueData(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('tentatives: $tentatives, ')
          ..write('dernierErreur: $dernierErreur, ')
          ..write('creeLe: $creeLe, ')
          ..write('prochainEssai: $prochainEssai, ')
          ..write('bloquee: $bloquee, ')
          ..write('libelle: $libelle')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, type, timestamp, payloadJson, tentatives,
      dernierErreur, creeLe, prochainEssai, bloquee, libelle);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OpQueueData &&
          other.id == this.id &&
          other.type == this.type &&
          other.timestamp == this.timestamp &&
          other.payloadJson == this.payloadJson &&
          other.tentatives == this.tentatives &&
          other.dernierErreur == this.dernierErreur &&
          other.creeLe == this.creeLe &&
          other.prochainEssai == this.prochainEssai &&
          other.bloquee == this.bloquee &&
          other.libelle == this.libelle);
}

class OpQueueCompanion extends UpdateCompanion<OpQueueData> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> timestamp;
  final Value<String> payloadJson;
  final Value<int> tentatives;
  final Value<String?> dernierErreur;
  final Value<String> creeLe;
  final Value<String?> prochainEssai;
  final Value<bool> bloquee;
  final Value<String?> libelle;
  final Value<int> rowid;
  const OpQueueCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.tentatives = const Value.absent(),
    this.dernierErreur = const Value.absent(),
    this.creeLe = const Value.absent(),
    this.prochainEssai = const Value.absent(),
    this.bloquee = const Value.absent(),
    this.libelle = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OpQueueCompanion.insert({
    required String id,
    required String type,
    required String timestamp,
    required String payloadJson,
    this.tentatives = const Value.absent(),
    this.dernierErreur = const Value.absent(),
    required String creeLe,
    this.prochainEssai = const Value.absent(),
    this.bloquee = const Value.absent(),
    this.libelle = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        timestamp = Value(timestamp),
        payloadJson = Value(payloadJson),
        creeLe = Value(creeLe);
  static Insertable<OpQueueData> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? timestamp,
    Expression<String>? payloadJson,
    Expression<int>? tentatives,
    Expression<String>? dernierErreur,
    Expression<String>? creeLe,
    Expression<String>? prochainEssai,
    Expression<bool>? bloquee,
    Expression<String>? libelle,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (timestamp != null) 'timestamp': timestamp,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (tentatives != null) 'tentatives': tentatives,
      if (dernierErreur != null) 'dernier_erreur': dernierErreur,
      if (creeLe != null) 'cree_le': creeLe,
      if (prochainEssai != null) 'prochain_essai': prochainEssai,
      if (bloquee != null) 'bloquee': bloquee,
      if (libelle != null) 'libelle': libelle,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OpQueueCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<String>? timestamp,
      Value<String>? payloadJson,
      Value<int>? tentatives,
      Value<String?>? dernierErreur,
      Value<String>? creeLe,
      Value<String?>? prochainEssai,
      Value<bool>? bloquee,
      Value<String?>? libelle,
      Value<int>? rowid}) {
    return OpQueueCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      payloadJson: payloadJson ?? this.payloadJson,
      tentatives: tentatives ?? this.tentatives,
      dernierErreur: dernierErreur ?? this.dernierErreur,
      creeLe: creeLe ?? this.creeLe,
      prochainEssai: prochainEssai ?? this.prochainEssai,
      bloquee: bloquee ?? this.bloquee,
      libelle: libelle ?? this.libelle,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<String>(timestamp.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (tentatives.present) {
      map['tentatives'] = Variable<int>(tentatives.value);
    }
    if (dernierErreur.present) {
      map['dernier_erreur'] = Variable<String>(dernierErreur.value);
    }
    if (creeLe.present) {
      map['cree_le'] = Variable<String>(creeLe.value);
    }
    if (prochainEssai.present) {
      map['prochain_essai'] = Variable<String>(prochainEssai.value);
    }
    if (bloquee.present) {
      map['bloquee'] = Variable<bool>(bloquee.value);
    }
    if (libelle.present) {
      map['libelle'] = Variable<String>(libelle.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OpQueueCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('tentatives: $tentatives, ')
          ..write('dernierErreur: $dernierErreur, ')
          ..write('creeLe: $creeLe, ')
          ..write('prochainEssai: $prochainEssai, ')
          ..write('bloquee: $bloquee, ')
          ..write('libelle: $libelle, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KvTable extends Kv with TableInfo<$KvTable, KvData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cleMeta = const VerificationMeta('cle');
  @override
  late final GeneratedColumn<String> cle = GeneratedColumn<String>(
      'cle', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valeurMeta = const VerificationMeta('valeur');
  @override
  late final GeneratedColumn<String> valeur = GeneratedColumn<String>(
      'valeur', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [cle, valeur];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv';
  @override
  VerificationContext validateIntegrity(Insertable<KvData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cle')) {
      context.handle(
          _cleMeta, cle.isAcceptableOrUnknown(data['cle']!, _cleMeta));
    } else if (isInserting) {
      context.missing(_cleMeta);
    }
    if (data.containsKey('valeur')) {
      context.handle(_valeurMeta,
          valeur.isAcceptableOrUnknown(data['valeur']!, _valeurMeta));
    } else if (isInserting) {
      context.missing(_valeurMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cle};
  @override
  KvData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvData(
      cle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cle'])!,
      valeur: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}valeur'])!,
    );
  }

  @override
  $KvTable createAlias(String alias) {
    return $KvTable(attachedDatabase, alias);
  }
}

class KvData extends DataClass implements Insertable<KvData> {
  final String cle;
  final String valeur;
  const KvData({required this.cle, required this.valeur});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cle'] = Variable<String>(cle);
    map['valeur'] = Variable<String>(valeur);
    return map;
  }

  KvCompanion toCompanion(bool nullToAbsent) {
    return KvCompanion(
      cle: Value(cle),
      valeur: Value(valeur),
    );
  }

  factory KvData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvData(
      cle: serializer.fromJson<String>(json['cle']),
      valeur: serializer.fromJson<String>(json['valeur']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cle': serializer.toJson<String>(cle),
      'valeur': serializer.toJson<String>(valeur),
    };
  }

  KvData copyWith({String? cle, String? valeur}) => KvData(
        cle: cle ?? this.cle,
        valeur: valeur ?? this.valeur,
      );
  KvData copyWithCompanion(KvCompanion data) {
    return KvData(
      cle: data.cle.present ? data.cle.value : this.cle,
      valeur: data.valeur.present ? data.valeur.value : this.valeur,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvData(')
          ..write('cle: $cle, ')
          ..write('valeur: $valeur')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cle, valeur);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvData && other.cle == this.cle && other.valeur == this.valeur);
}

class KvCompanion extends UpdateCompanion<KvData> {
  final Value<String> cle;
  final Value<String> valeur;
  final Value<int> rowid;
  const KvCompanion({
    this.cle = const Value.absent(),
    this.valeur = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvCompanion.insert({
    required String cle,
    required String valeur,
    this.rowid = const Value.absent(),
  })  : cle = Value(cle),
        valeur = Value(valeur);
  static Insertable<KvData> custom({
    Expression<String>? cle,
    Expression<String>? valeur,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cle != null) 'cle': cle,
      if (valeur != null) 'valeur': valeur,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvCompanion copyWith(
      {Value<String>? cle, Value<String>? valeur, Value<int>? rowid}) {
    return KvCompanion(
      cle: cle ?? this.cle,
      valeur: valeur ?? this.valeur,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cle.present) {
      map['cle'] = Variable<String>(cle.value);
    }
    if (valeur.present) {
      map['valeur'] = Variable<String>(valeur.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvCompanion(')
          ..write('cle: $cle, ')
          ..write('valeur: $valeur, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConflitsTable extends Conflits with TableInfo<$ConflitsTable, Conflit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConflitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _libelleMeta =
      const VerificationMeta('libelle');
  @override
  late final GeneratedColumn<String> libelle = GeneratedColumn<String>(
      'libelle', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tentativeJsonMeta =
      const VerificationMeta('tentativeJson');
  @override
  late final GeneratedColumn<String> tentativeJson = GeneratedColumn<String>(
      'tentative_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _serveurJsonMeta =
      const VerificationMeta('serveurJson');
  @override
  late final GeneratedColumn<String> serveurJson = GeneratedColumn<String>(
      'serveur_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _detecteLeMeta =
      const VerificationMeta('detecteLe');
  @override
  late final GeneratedColumn<String> detecteLe = GeneratedColumn<String>(
      'detecte_le', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, type, libelle, tentativeJson, serveurJson, detecteLe];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conflits';
  @override
  VerificationContext validateIntegrity(Insertable<Conflit> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('libelle')) {
      context.handle(_libelleMeta,
          libelle.isAcceptableOrUnknown(data['libelle']!, _libelleMeta));
    } else if (isInserting) {
      context.missing(_libelleMeta);
    }
    if (data.containsKey('tentative_json')) {
      context.handle(
          _tentativeJsonMeta,
          tentativeJson.isAcceptableOrUnknown(
              data['tentative_json']!, _tentativeJsonMeta));
    } else if (isInserting) {
      context.missing(_tentativeJsonMeta);
    }
    if (data.containsKey('serveur_json')) {
      context.handle(
          _serveurJsonMeta,
          serveurJson.isAcceptableOrUnknown(
              data['serveur_json']!, _serveurJsonMeta));
    } else if (isInserting) {
      context.missing(_serveurJsonMeta);
    }
    if (data.containsKey('detecte_le')) {
      context.handle(_detecteLeMeta,
          detecteLe.isAcceptableOrUnknown(data['detecte_le']!, _detecteLeMeta));
    } else if (isInserting) {
      context.missing(_detecteLeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conflit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conflit(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      libelle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}libelle'])!,
      tentativeJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tentative_json'])!,
      serveurJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}serveur_json'])!,
      detecteLe: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detecte_le'])!,
    );
  }

  @override
  $ConflitsTable createAlias(String alias) {
    return $ConflitsTable(attachedDatabase, alias);
  }
}

class Conflit extends DataClass implements Insertable<Conflit> {
  final String id;
  final String type;
  final String libelle;

  /// Ce que l'appareil a tenté d'écrire.
  final String tentativeJson;

  /// Ce que le serveur a de son côté.
  final String serveurJson;
  final String detecteLe;
  const Conflit(
      {required this.id,
      required this.type,
      required this.libelle,
      required this.tentativeJson,
      required this.serveurJson,
      required this.detecteLe});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['libelle'] = Variable<String>(libelle);
    map['tentative_json'] = Variable<String>(tentativeJson);
    map['serveur_json'] = Variable<String>(serveurJson);
    map['detecte_le'] = Variable<String>(detecteLe);
    return map;
  }

  ConflitsCompanion toCompanion(bool nullToAbsent) {
    return ConflitsCompanion(
      id: Value(id),
      type: Value(type),
      libelle: Value(libelle),
      tentativeJson: Value(tentativeJson),
      serveurJson: Value(serveurJson),
      detecteLe: Value(detecteLe),
    );
  }

  factory Conflit.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conflit(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      libelle: serializer.fromJson<String>(json['libelle']),
      tentativeJson: serializer.fromJson<String>(json['tentativeJson']),
      serveurJson: serializer.fromJson<String>(json['serveurJson']),
      detecteLe: serializer.fromJson<String>(json['detecteLe']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'libelle': serializer.toJson<String>(libelle),
      'tentativeJson': serializer.toJson<String>(tentativeJson),
      'serveurJson': serializer.toJson<String>(serveurJson),
      'detecteLe': serializer.toJson<String>(detecteLe),
    };
  }

  Conflit copyWith(
          {String? id,
          String? type,
          String? libelle,
          String? tentativeJson,
          String? serveurJson,
          String? detecteLe}) =>
      Conflit(
        id: id ?? this.id,
        type: type ?? this.type,
        libelle: libelle ?? this.libelle,
        tentativeJson: tentativeJson ?? this.tentativeJson,
        serveurJson: serveurJson ?? this.serveurJson,
        detecteLe: detecteLe ?? this.detecteLe,
      );
  Conflit copyWithCompanion(ConflitsCompanion data) {
    return Conflit(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      libelle: data.libelle.present ? data.libelle.value : this.libelle,
      tentativeJson: data.tentativeJson.present
          ? data.tentativeJson.value
          : this.tentativeJson,
      serveurJson:
          data.serveurJson.present ? data.serveurJson.value : this.serveurJson,
      detecteLe: data.detecteLe.present ? data.detecteLe.value : this.detecteLe,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conflit(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('libelle: $libelle, ')
          ..write('tentativeJson: $tentativeJson, ')
          ..write('serveurJson: $serveurJson, ')
          ..write('detecteLe: $detecteLe')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, type, libelle, tentativeJson, serveurJson, detecteLe);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conflit &&
          other.id == this.id &&
          other.type == this.type &&
          other.libelle == this.libelle &&
          other.tentativeJson == this.tentativeJson &&
          other.serveurJson == this.serveurJson &&
          other.detecteLe == this.detecteLe);
}

class ConflitsCompanion extends UpdateCompanion<Conflit> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> libelle;
  final Value<String> tentativeJson;
  final Value<String> serveurJson;
  final Value<String> detecteLe;
  final Value<int> rowid;
  const ConflitsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.libelle = const Value.absent(),
    this.tentativeJson = const Value.absent(),
    this.serveurJson = const Value.absent(),
    this.detecteLe = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConflitsCompanion.insert({
    required String id,
    required String type,
    required String libelle,
    required String tentativeJson,
    required String serveurJson,
    required String detecteLe,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        libelle = Value(libelle),
        tentativeJson = Value(tentativeJson),
        serveurJson = Value(serveurJson),
        detecteLe = Value(detecteLe);
  static Insertable<Conflit> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? libelle,
    Expression<String>? tentativeJson,
    Expression<String>? serveurJson,
    Expression<String>? detecteLe,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (libelle != null) 'libelle': libelle,
      if (tentativeJson != null) 'tentative_json': tentativeJson,
      if (serveurJson != null) 'serveur_json': serveurJson,
      if (detecteLe != null) 'detecte_le': detecteLe,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConflitsCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<String>? libelle,
      Value<String>? tentativeJson,
      Value<String>? serveurJson,
      Value<String>? detecteLe,
      Value<int>? rowid}) {
    return ConflitsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      libelle: libelle ?? this.libelle,
      tentativeJson: tentativeJson ?? this.tentativeJson,
      serveurJson: serveurJson ?? this.serveurJson,
      detecteLe: detecteLe ?? this.detecteLe,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (libelle.present) {
      map['libelle'] = Variable<String>(libelle.value);
    }
    if (tentativeJson.present) {
      map['tentative_json'] = Variable<String>(tentativeJson.value);
    }
    if (serveurJson.present) {
      map['serveur_json'] = Variable<String>(serveurJson.value);
    }
    if (detecteLe.present) {
      map['detecte_le'] = Variable<String>(detecteLe.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConflitsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('libelle: $libelle, ')
          ..write('tentativeJson: $tentativeJson, ')
          ..write('serveurJson: $serveurJson, ')
          ..write('detecteLe: $detecteLe, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RecordsTable records = $RecordsTable(this);
  late final $OpQueueTable opQueue = $OpQueueTable(this);
  late final $KvTable kv = $KvTable(this);
  late final $ConflitsTable conflits = $ConflitsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [records, opQueue, kv, conflits];
}

typedef $$RecordsTableCreateCompanionBuilder = RecordsCompanion Function({
  required String kind,
  required String id,
  required String json,
  Value<int?> rev,
  Value<String?> updatedAt,
  Value<int> rowid,
});
typedef $$RecordsTableUpdateCompanionBuilder = RecordsCompanion Function({
  Value<String> kind,
  Value<String> id,
  Value<String> json,
  Value<int?> rev,
  Value<String?> updatedAt,
  Value<int> rowid,
});

class $$RecordsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RecordsTable,
    Record,
    $$RecordsTableFilterComposer,
    $$RecordsTableOrderingComposer,
    $$RecordsTableCreateCompanionBuilder,
    $$RecordsTableUpdateCompanionBuilder> {
  $$RecordsTableTableManager(_$AppDatabase db, $RecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$RecordsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$RecordsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> kind = const Value.absent(),
            Value<String> id = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<int?> rev = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecordsCompanion(
            kind: kind,
            id: id,
            json: json,
            rev: rev,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String kind,
            required String id,
            required String json,
            Value<int?> rev = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecordsCompanion.insert(
            kind: kind,
            id: id,
            json: json,
            rev: rev,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$RecordsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableFilterComposer(super.$state);
  ColumnFilters<String> get kind => $state.composableBuilder(
      column: $state.table.kind,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get json => $state.composableBuilder(
      column: $state.table.json,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get rev => $state.composableBuilder(
      column: $state.table.rev,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$RecordsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get kind => $state.composableBuilder(
      column: $state.table.kind,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get json => $state.composableBuilder(
      column: $state.table.json,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get rev => $state.composableBuilder(
      column: $state.table.rev,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$OpQueueTableCreateCompanionBuilder = OpQueueCompanion Function({
  required String id,
  required String type,
  required String timestamp,
  required String payloadJson,
  Value<int> tentatives,
  Value<String?> dernierErreur,
  required String creeLe,
  Value<String?> prochainEssai,
  Value<bool> bloquee,
  Value<String?> libelle,
  Value<int> rowid,
});
typedef $$OpQueueTableUpdateCompanionBuilder = OpQueueCompanion Function({
  Value<String> id,
  Value<String> type,
  Value<String> timestamp,
  Value<String> payloadJson,
  Value<int> tentatives,
  Value<String?> dernierErreur,
  Value<String> creeLe,
  Value<String?> prochainEssai,
  Value<bool> bloquee,
  Value<String?> libelle,
  Value<int> rowid,
});

class $$OpQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OpQueueTable,
    OpQueueData,
    $$OpQueueTableFilterComposer,
    $$OpQueueTableOrderingComposer,
    $$OpQueueTableCreateCompanionBuilder,
    $$OpQueueTableUpdateCompanionBuilder> {
  $$OpQueueTableTableManager(_$AppDatabase db, $OpQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$OpQueueTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$OpQueueTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> timestamp = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<int> tentatives = const Value.absent(),
            Value<String?> dernierErreur = const Value.absent(),
            Value<String> creeLe = const Value.absent(),
            Value<String?> prochainEssai = const Value.absent(),
            Value<bool> bloquee = const Value.absent(),
            Value<String?> libelle = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OpQueueCompanion(
            id: id,
            type: type,
            timestamp: timestamp,
            payloadJson: payloadJson,
            tentatives: tentatives,
            dernierErreur: dernierErreur,
            creeLe: creeLe,
            prochainEssai: prochainEssai,
            bloquee: bloquee,
            libelle: libelle,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String type,
            required String timestamp,
            required String payloadJson,
            Value<int> tentatives = const Value.absent(),
            Value<String?> dernierErreur = const Value.absent(),
            required String creeLe,
            Value<String?> prochainEssai = const Value.absent(),
            Value<bool> bloquee = const Value.absent(),
            Value<String?> libelle = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OpQueueCompanion.insert(
            id: id,
            type: type,
            timestamp: timestamp,
            payloadJson: payloadJson,
            tentatives: tentatives,
            dernierErreur: dernierErreur,
            creeLe: creeLe,
            prochainEssai: prochainEssai,
            bloquee: bloquee,
            libelle: libelle,
            rowid: rowid,
          ),
        ));
}

class $$OpQueueTableFilterComposer
    extends FilterComposer<_$AppDatabase, $OpQueueTable> {
  $$OpQueueTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get timestamp => $state.composableBuilder(
      column: $state.table.timestamp,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get payloadJson => $state.composableBuilder(
      column: $state.table.payloadJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get tentatives => $state.composableBuilder(
      column: $state.table.tentatives,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get dernierErreur => $state.composableBuilder(
      column: $state.table.dernierErreur,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get creeLe => $state.composableBuilder(
      column: $state.table.creeLe,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get prochainEssai => $state.composableBuilder(
      column: $state.table.prochainEssai,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get bloquee => $state.composableBuilder(
      column: $state.table.bloquee,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get libelle => $state.composableBuilder(
      column: $state.table.libelle,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$OpQueueTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $OpQueueTable> {
  $$OpQueueTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get timestamp => $state.composableBuilder(
      column: $state.table.timestamp,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get payloadJson => $state.composableBuilder(
      column: $state.table.payloadJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get tentatives => $state.composableBuilder(
      column: $state.table.tentatives,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get dernierErreur => $state.composableBuilder(
      column: $state.table.dernierErreur,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get creeLe => $state.composableBuilder(
      column: $state.table.creeLe,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get prochainEssai => $state.composableBuilder(
      column: $state.table.prochainEssai,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get bloquee => $state.composableBuilder(
      column: $state.table.bloquee,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get libelle => $state.composableBuilder(
      column: $state.table.libelle,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$KvTableCreateCompanionBuilder = KvCompanion Function({
  required String cle,
  required String valeur,
  Value<int> rowid,
});
typedef $$KvTableUpdateCompanionBuilder = KvCompanion Function({
  Value<String> cle,
  Value<String> valeur,
  Value<int> rowid,
});

class $$KvTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KvTable,
    KvData,
    $$KvTableFilterComposer,
    $$KvTableOrderingComposer,
    $$KvTableCreateCompanionBuilder,
    $$KvTableUpdateCompanionBuilder> {
  $$KvTableTableManager(_$AppDatabase db, $KvTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$KvTableFilterComposer(ComposerState(db, table)),
          orderingComposer: $$KvTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> cle = const Value.absent(),
            Value<String> valeur = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KvCompanion(
            cle: cle,
            valeur: valeur,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String cle,
            required String valeur,
            Value<int> rowid = const Value.absent(),
          }) =>
              KvCompanion.insert(
            cle: cle,
            valeur: valeur,
            rowid: rowid,
          ),
        ));
}

class $$KvTableFilterComposer extends FilterComposer<_$AppDatabase, $KvTable> {
  $$KvTableFilterComposer(super.$state);
  ColumnFilters<String> get cle => $state.composableBuilder(
      column: $state.table.cle,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get valeur => $state.composableBuilder(
      column: $state.table.valeur,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$KvTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $KvTable> {
  $$KvTableOrderingComposer(super.$state);
  ColumnOrderings<String> get cle => $state.composableBuilder(
      column: $state.table.cle,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get valeur => $state.composableBuilder(
      column: $state.table.valeur,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$ConflitsTableCreateCompanionBuilder = ConflitsCompanion Function({
  required String id,
  required String type,
  required String libelle,
  required String tentativeJson,
  required String serveurJson,
  required String detecteLe,
  Value<int> rowid,
});
typedef $$ConflitsTableUpdateCompanionBuilder = ConflitsCompanion Function({
  Value<String> id,
  Value<String> type,
  Value<String> libelle,
  Value<String> tentativeJson,
  Value<String> serveurJson,
  Value<String> detecteLe,
  Value<int> rowid,
});

class $$ConflitsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConflitsTable,
    Conflit,
    $$ConflitsTableFilterComposer,
    $$ConflitsTableOrderingComposer,
    $$ConflitsTableCreateCompanionBuilder,
    $$ConflitsTableUpdateCompanionBuilder> {
  $$ConflitsTableTableManager(_$AppDatabase db, $ConflitsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$ConflitsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$ConflitsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> libelle = const Value.absent(),
            Value<String> tentativeJson = const Value.absent(),
            Value<String> serveurJson = const Value.absent(),
            Value<String> detecteLe = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConflitsCompanion(
            id: id,
            type: type,
            libelle: libelle,
            tentativeJson: tentativeJson,
            serveurJson: serveurJson,
            detecteLe: detecteLe,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String type,
            required String libelle,
            required String tentativeJson,
            required String serveurJson,
            required String detecteLe,
            Value<int> rowid = const Value.absent(),
          }) =>
              ConflitsCompanion.insert(
            id: id,
            type: type,
            libelle: libelle,
            tentativeJson: tentativeJson,
            serveurJson: serveurJson,
            detecteLe: detecteLe,
            rowid: rowid,
          ),
        ));
}

class $$ConflitsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $ConflitsTable> {
  $$ConflitsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get libelle => $state.composableBuilder(
      column: $state.table.libelle,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get tentativeJson => $state.composableBuilder(
      column: $state.table.tentativeJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get serveurJson => $state.composableBuilder(
      column: $state.table.serveurJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get detecteLe => $state.composableBuilder(
      column: $state.table.detecteLe,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$ConflitsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $ConflitsTable> {
  $$ConflitsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get libelle => $state.composableBuilder(
      column: $state.table.libelle,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get tentativeJson => $state.composableBuilder(
      column: $state.table.tentativeJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get serveurJson => $state.composableBuilder(
      column: $state.table.serveurJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get detecteLe => $state.composableBuilder(
      column: $state.table.detecteLe,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RecordsTableTableManager get records =>
      $$RecordsTableTableManager(_db, _db.records);
  $$OpQueueTableTableManager get opQueue =>
      $$OpQueueTableTableManager(_db, _db.opQueue);
  $$KvTableTableManager get kv => $$KvTableTableManager(_db, _db.kv);
  $$ConflitsTableTableManager get conflits =>
      $$ConflitsTableTableManager(_db, _db.conflits);
}
