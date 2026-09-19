class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

// Only app-owned messages are suitable for the UI. SDK exceptions can contain
// request URLs, SQL details, paths or private response values.
String safeErrorMessage(Object? error) => error is AppException
    ? error.message
    : 'No se han podido cargar los datos. Inténtalo de nuevo.';

class AuthenticationException extends AppException {
  const AuthenticationException(super.message);
}

class ConfigurationException extends AppException {
  const ConfigurationException(super.message);
}

class NetworkException extends AppException {
  const NetworkException(super.message);
}

class SecureStorageException extends AppException {
  const SecureStorageException(super.message);
}

class LoginPreparationException extends AppException {
  const LoginPreparationException(super.message);
}

class SessionExpiredException extends AppException {
  const SessionExpiredException(super.message);
}

class UnexpectedResponseException extends AppException {
  const UnexpectedResponseException(super.message);
}

class PendingIntegrationException extends AppException {
  const PendingIntegrationException(super.message);
}
