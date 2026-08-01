abstract interface class DatabaseLifecycle {
  Future<T> withClosedDatabase<T>(Future<T> Function(String databasePath) work);

  Future<void> reopen();
}
