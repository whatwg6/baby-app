abstract interface class DatabaseLifecycle {
  Future<T> withClosedDatabase<T>(Future<T> Function(String databasePath) work);

  Future<void> reopen();
}

class DatabaseLifecycleReopenException implements Exception {
  const DatabaseLifecycleReopenException({
    required this.operationError,
    required this.operationStackTrace,
    required this.reopenError,
    required this.reopenStackTrace,
  });

  final Object? operationError;
  final StackTrace? operationStackTrace;
  final Object reopenError;
  final StackTrace reopenStackTrace;

  @override
  String toString() => operationError == null
      ? 'Database reopen failed: $reopenError'
      : 'Database operation failed ($operationError) and reopen failed: '
            '$reopenError';
}
