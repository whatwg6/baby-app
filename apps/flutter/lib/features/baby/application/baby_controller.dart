import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/baby_repository.dart';
import '../../../domain/models/baby.dart';
import '../../../domain/validation/baby_validator.dart';

class BabyController extends ChangeNotifier {
  BabyController(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final BabyRepository _repository;
  final DateTime Function() _now;

  AsyncValue<Baby?> _state = const AsyncData(null);
  AsyncValue<Baby?> get state => _state;
  Baby? get baby => _state.whenOrNull(data: (value) => value);
  bool _isSaving = false;
  bool get isSaving => _isSaving;
  Object? _saveError;
  Object? get saveError => _saveError;

  Future<void>? _loadFuture;

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    _setState(const AsyncLoading());
    try {
      _setState(AsyncData(await _repository.getCurrent()));
    } catch (error, stackTrace) {
      _setState(AsyncError(error, stackTrace));
    }
  }

  Future<void> reload() async {
    _loadFuture = null;
    await load();
  }

  Future<void> save(BabyDraft draft) async {
    final normalized = validateBabyDraft(draft, now: _now());
    final current = baby;
    _isSaving = true;
    _saveError = null;
    notifyListeners();
    try {
      final saved = current == null
          ? await _repository.create(normalized)
          : await _repository.update(current.id, normalized);
      _setState(AsyncData(saved));
    } catch (error) {
      _saveError = error;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _setState(AsyncValue<Baby?> value) {
    _state = value;
    notifyListeners();
  }
}
