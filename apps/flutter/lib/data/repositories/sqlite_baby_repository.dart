import 'package:uuid/uuid.dart';

import '../../domain/models/baby.dart';
import '../database/app_database.dart';
import 'baby_repository.dart';

class SqliteBabyRepository implements BabyRepository {
  SqliteBabyRepository(
    this._appDatabase, {
    this._uuid = const Uuid(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _appDatabase;
  final Uuid _uuid;
  final DateTime Function() _now;

  @override
  Future<Baby> create(BabyDraft draft) =>
      _appDatabase.transaction((database) async {
        final existing = await database.query('baby', limit: 1);
        if (existing.isNotEmpty) {
          throw StateError('A baby profile already exists.');
        }
        final instant = _now().toUtc();
        final baby = Baby(
          id: _uuid.v4(),
          name: draft.name,
          birthDate: draft.birthDate,
          sex: draft.sex,
          avatarPath: draft.avatarPath,
          createdAt: instant,
          updatedAt: instant,
        );
        await database.insert('baby', _toRow(baby));
        return baby;
      });

  @override
  Future<void> delete(String id) => _appDatabase.write((database) async {
    await database.delete('baby', where: 'id = ?', whereArgs: [id]);
  });

  @override
  Future<Baby?> get(String id) => _appDatabase.read((database) async {
    final rows = await database.query(
      'baby',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  });

  @override
  Future<Baby?> getCurrent() => _appDatabase.read((database) async {
    final rows = await database.query('baby', limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.single);
  });

  @override
  Future<Baby> update(String id, BabyDraft draft) =>
      _appDatabase.transaction((database) async {
        final rows = await database.query(
          'baby',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Baby not found: $id');
        }
        final existing = _fromRow(rows.single);
        final baby = Baby(
          id: id,
          name: draft.name,
          birthDate: draft.birthDate,
          sex: draft.sex,
          avatarPath: draft.avatarPath,
          createdAt: existing.createdAt,
          updatedAt: _now().toUtc(),
        );
        await database.update(
          'baby',
          _toRow(baby),
          where: 'id = ?',
          whereArgs: [id],
        );
        return baby;
      });
}

Map<String, Object?> _toRow(Baby baby) => {
  'id': baby.id,
  'name': baby.name,
  'birth_date': baby.birthDate,
  'sex': baby.sex,
  'avatar_path': baby.avatarPath,
  'created_at': baby.createdAt.toUtc().toIso8601String(),
  'updated_at': baby.updatedAt.toUtc().toIso8601String(),
};

Baby _fromRow(Map<String, Object?> row) => Baby(
  id: row['id']! as String,
  name: row['name']! as String,
  birthDate: row['birth_date']! as String,
  sex: row['sex'] as String?,
  avatarPath: row['avatar_path'] as String?,
  createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
  updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
);
