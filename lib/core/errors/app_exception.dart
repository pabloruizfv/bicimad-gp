class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthenticationException extends AppException {
  const AuthenticationException(super.message);
}

class PendingIntegrationException extends AppException {
  const PendingIntegrationException(super.message);
}
