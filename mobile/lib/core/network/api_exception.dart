class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? cause;

  const ApiException({this.statusCode, required this.message, this.cause});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'ApiException(status=$statusCode, msg=$message)';
}
