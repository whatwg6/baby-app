import 'dart:async';

abstract interface class DestructiveOperationGate {
  Future<T> run<T>(Future<T> Function() operation);
}

final class SerialDestructiveOperationGate implements DestructiveOperationGate {
  Future<void> _tail = Future<void>.value();

  @override
  Future<T> run<T>(Future<T> Function() operation) {
    final predecessor = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return predecessor.then((_) => operation()).whenComplete(release.complete);
  }
}
