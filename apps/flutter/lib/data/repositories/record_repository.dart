import '../../domain/models/attachment.dart';
import '../../domain/models/record_draft.dart';
import '../../domain/models/timeline_record.dart';

abstract interface class RecordTransaction {
  Future<TimelineRecord> create(NewRecordInput input);

  Future<TimelineRecord> update(String id, NewRecordInput input);

  Future<List<Attachment>> delete(String id);
}

abstract interface class RecordRepository implements RecordTransaction {
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}});

  Future<TimelineRecord?> get(String id);

  Future<T> inTransaction<T>(
    Future<T> Function(RecordTransaction transaction) work,
  );
}
