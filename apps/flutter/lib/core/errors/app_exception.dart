/// Base class for errors that are safe to show to an app user.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when user-supplied domain input does not meet a rule.
class ValidationException extends AppException {
  const ValidationException(super.message, {this.field});

  /// The affected input field when one can be identified.
  final String? field;
}
