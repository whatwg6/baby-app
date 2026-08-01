import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/models/attachment.dart';
import '../../domain/models/record_draft.dart';
import '../../domain/models/timeline_record.dart';
import '../database/app_database.dart';
import 'record_repository.dart';

class SqliteRecordRepository implements RecordRepository {
  SqliteRecordRepository(
    this._appDatabase, {
    this._uuid = const Uuid(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _appDatabase;
  final Uuid _uuid;
  final DateTime Function() _now;

  @override
  Future<TimelineRecord> create(NewRecordInput input) =>
      inTransaction((transaction) => transaction.create(input));

  @override
  Future<List<Attachment>> delete(String id) =>
      inTransaction((transaction) => transaction.delete(id));

  @override
  Future<TimelineRecord?> get(String id) =>
      _appDatabase.read((database) => _get(database, id));

  @override
  Future<T> inTransaction<T>(
    Future<T> Function(RecordTransaction transaction) work,
  ) => _appDatabase.transaction(
    (database) =>
        work(_SqliteRecordTransaction(database, uuid: _uuid, now: _now)),
  );

  @override
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}}) =>
      _appDatabase.read((database) async {
        final typeNames = types.map((type) => type.name).toList();
        final rows = await database.query(
          'records',
          where: typeNames.isEmpty
              ? null
              : 'type IN (${List.filled(typeNames.length, '?').join(', ')})',
          whereArgs: typeNames.isEmpty ? null : typeNames,
          orderBy: 'occurred_at DESC',
        );
        return Future.wait(rows.map((row) => _recordFromRow(database, row)));
      });

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) =>
      inTransaction((transaction) => transaction.update(id, input));
}

class _SqliteRecordTransaction implements RecordTransaction {
  _SqliteRecordTransaction(
    this._database, {
    required this._uuid,
    required this._now,
  });

  final DatabaseExecutor _database;
  final Uuid _uuid;
  final DateTime Function() _now;

  @override
  Future<TimelineRecord> create(NewRecordInput input) async {
    _validateDetails(input);
    final id = _uuid.v4();
    final instant = _now().toUtc();
    await _database.insert('records', {
      'id': id,
      'type': input.type.name,
      'occurred_at': input.occurredAt.toUtc().toIso8601String(),
      'note': input.note,
      'created_at': instant.toIso8601String(),
      'updated_at': instant.toIso8601String(),
    });
    await _insertDetails(_database, id, input.details, _uuid);
    await _insertAttachments(
      _database,
      id,
      input.attachments,
      uuid: _uuid,
      createdAt: instant,
    );
    return (await _get(_database, id))!;
  }

  @override
  Future<List<Attachment>> delete(String id) async {
    final record = await _get(_database, id);
    if (record == null) {
      return const [];
    }
    await _database.delete('records', where: 'id = ?', whereArgs: [id]);
    return record.attachments;
  }

  @override
  Future<TimelineRecord> update(String id, NewRecordInput input) async {
    _validateDetails(input);
    final existing = await _get(_database, id);
    if (existing == null) {
      throw StateError('Record not found: $id');
    }

    await _database.update(
      'records',
      {
        'type': input.type.name,
        'occurred_at': input.occurredAt.toUtc().toIso8601String(),
        'note': input.note,
        'updated_at': _now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    for (final table in [
      'growth_details',
      'activity_details',
      'milestone_details',
    ]) {
      await _database.delete(table, where: 'record_id = ?', whereArgs: [id]);
    }
    await _database.delete(
      'attachments',
      where: 'record_id = ?',
      whereArgs: [id],
    );
    await _insertDetails(_database, id, input.details, _uuid);

    final existingAttachments = {
      for (final attachment in existing.attachments)
        attachment.id: attachment.createdAt,
    };
    await _insertAttachments(
      _database,
      id,
      input.attachments,
      uuid: _uuid,
      createdAt: _now().toUtc(),
      existingCreatedAt: existingAttachments,
    );
    return (await _get(_database, id))!;
  }
}

Future<TimelineRecord?> _get(DatabaseExecutor database, String id) async {
  final rows = await database.query(
    'records',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isEmpty ? null : _recordFromRow(database, rows.single);
}

Future<TimelineRecord> _recordFromRow(
  DatabaseExecutor database,
  Map<String, Object?> row,
) async {
  final id = row['id']! as String;
  final type = RecordType.values.byName(row['type']! as String);
  return TimelineRecord(
    id: id,
    type: type,
    occurredAt: DateTime.parse(row['occurred_at']! as String).toUtc(),
    note: row['note'] as String?,
    details: await _readDetails(database, id, type),
    attachments: await _readAttachments(database, id),
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
  );
}

Future<RecordDetails?> _readDetails(
  DatabaseExecutor database,
  String recordId,
  RecordType type,
) async {
  switch (type) {
    case RecordType.moment:
      return null;
    case RecordType.growth:
      final rows = await database.query(
        'growth_details',
        where: 'record_id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      return RecordDetails.growth(
        heightCm: (row['height_cm'] as num?)?.toDouble(),
        weightKg: (row['weight_kg'] as num?)?.toDouble(),
        headCm: (row['head_cm'] as num?)?.toDouble(),
      );
    case RecordType.activity:
      final rows = await database.query(
        'activity_details',
        where: 'record_id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      return RecordDetails.activity(
        activityType: ActivityType.values.byName(
          row['activity_type']! as String,
        ),
        amount: (row['amount'] as num?)?.toDouble(),
        durationMinutes: (row['duration_minutes'] as num?)?.toInt(),
      );
    case RecordType.milestone:
      final rows = await database.query(
        'milestone_details',
        where: 'record_id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      return RecordDetails.milestone(
        title: row['title']! as String,
        presetKey: row['preset_key'] as String?,
      );
  }
}

Future<List<Attachment>> _readAttachments(
  DatabaseExecutor database,
  String recordId,
) async {
  final rows = await database.query(
    'attachments',
    where: 'record_id = ?',
    whereArgs: [recordId],
    orderBy: 'created_at ASC, id ASC',
  );
  return rows
      .map(
        (row) => Attachment(
          id: row['id']! as String,
          recordId: row['record_id']! as String,
          mediaType: MediaType.values.byName(row['media_type']! as String),
          filePath: row['file_path']! as String,
          thumbnailPath: row['thumbnail_path'] as String?,
          createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
        ),
      )
      .toList();
}

Future<void> _insertDetails(
  DatabaseExecutor database,
  String recordId,
  RecordDetails? details,
  Uuid uuid,
) async {
  switch (details) {
    case null:
      return;
    case GrowthDetails():
      await database.insert('growth_details', {
        'id': uuid.v4(),
        'record_id': recordId,
        'height_cm': details.heightCm,
        'weight_kg': details.weightKg,
        'head_cm': details.headCm,
      });
    case ActivityDetails():
      await database.insert('activity_details', {
        'id': uuid.v4(),
        'record_id': recordId,
        'activity_type': details.activityType.name,
        'amount': details.amount,
        'duration_minutes': details.durationMinutes,
      });
    case MilestoneDetails():
      await database.insert('milestone_details', {
        'id': uuid.v4(),
        'record_id': recordId,
        'title': details.title,
        'preset_key': details.presetKey,
      });
  }
}

Future<void> _insertAttachments(
  DatabaseExecutor database,
  String recordId,
  List<NewAttachmentInput> attachments, {
  required Uuid uuid,
  required DateTime createdAt,
  Map<String, DateTime> existingCreatedAt = const {},
}) async {
  for (final input in attachments) {
    final id = input.id ?? uuid.v4();
    await database.insert('attachments', {
      'id': id,
      'record_id': recordId,
      'media_type': input.mediaType.name,
      'file_path': input.filePath,
      'thumbnail_path': input.thumbnailPath,
      'created_at': (existingCreatedAt[id] ?? createdAt)
          .toUtc()
          .toIso8601String(),
    });
  }
}

void _validateDetails(NewRecordInput input) {
  final isMatching = switch (input.type) {
    RecordType.moment => input.details == null,
    RecordType.growth => input.details is GrowthDetails,
    RecordType.activity => input.details is ActivityDetails,
    RecordType.milestone => input.details is MilestoneDetails,
  };
  if (!isMatching) {
    throw const ValidationException('记录类型与详情不匹配。', field: 'details');
  }
}
