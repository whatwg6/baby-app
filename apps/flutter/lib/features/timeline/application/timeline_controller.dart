import 'package:flutter/foundation.dart';

import '../../../data/repositories/record_repository.dart';
import '../../../domain/models/timeline_record.dart';

@immutable
class TimelineState {
  const TimelineState({
    this.records = const [],
    this.selectedTypes = const {},
    this.isLoading = false,
    this.errorMessage,
  });

  final List<TimelineRecord> records;
  final Set<RecordType> selectedTypes;
  final bool isLoading;
  final String? errorMessage;

  TimelineState copyWith({
    List<TimelineRecord>? records,
    Set<RecordType>? selectedTypes,
    bool? isLoading,
    Object? errorMessage = _noChange,
  }) => TimelineState(
    records: records ?? this.records,
    selectedTypes: selectedTypes ?? this.selectedTypes,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: identical(errorMessage, _noChange)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

const _noChange = Object();

class TimelineController extends ChangeNotifier {
  TimelineController(this._repository);

  final RecordRepository _repository;
  TimelineState _state = const TimelineState();
  TimelineState get state => _state;
  Future<void>? _loadFuture;
  var _requestGeneration = 0;

  Future<void> load() => _loadFuture ??= _reload();

  Future<void> reload() async {
    _loadFuture = _reload();
    await _loadFuture;
  }

  Future<void> toggleType(RecordType type) async {
    final selected = {..._state.selectedTypes};
    if (!selected.add(type)) selected.remove(type);
    _setState(_state.copyWith(selectedTypes: selected));
    await reload();
  }

  Future<void> clearFilters() async {
    if (_state.selectedTypes.isEmpty) return;
    _setState(_state.copyWith(selectedTypes: const {}));
    await reload();
  }

  Future<void> _reload() async {
    final requestGeneration = ++_requestGeneration;
    final requestedTypes = _state.selectedTypes;
    _setState(_state.copyWith(isLoading: true, errorMessage: null));
    try {
      final records = await _repository.list(types: requestedTypes);
      if (!_isCurrentRequest(requestGeneration, requestedTypes)) return;
      _setState(_state.copyWith(records: records, isLoading: false));
    } catch (_) {
      if (!_isCurrentRequest(requestGeneration, requestedTypes)) return;
      _setState(_state.copyWith(isLoading: false, errorMessage: '无法读取记录，请重试'));
    }
  }

  bool _isCurrentRequest(int generation, Set<RecordType> types) =>
      generation == _requestGeneration &&
      setEquals(types, _state.selectedTypes);

  void _setState(TimelineState value) {
    _state = value;
    notifyListeners();
  }
}
