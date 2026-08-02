Future<void> disposeBestEffort(Future<void> Function() dispose) async {
  try {
    await dispose();
  } catch (_) {
    // Cleanup failures must not replace the operation or teardown outcome.
  }
}
