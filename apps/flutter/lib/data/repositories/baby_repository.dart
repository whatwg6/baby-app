import '../../domain/models/baby.dart';

abstract interface class BabyRepository {
  Future<Baby> create(BabyDraft draft);

  /// Returns the sole profile stored by this single-baby application.
  Future<Baby?> getCurrent();

  Future<Baby?> get(String id);

  Future<Baby> update(String id, BabyDraft draft);

  Future<void> delete(String id);
}
