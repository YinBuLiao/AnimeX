import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';

Dio buildDio({
  required ServerConfig config,
  required SessionStore sessionStore,
}) {
  final dio = Dio(BaseOptions(
    baseUrl: config.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ));

  if (config.allowSelfSigned) {
    final adapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    dio.httpClientAdapter = adapter;
  }

  dio.interceptors.add(_AuthInterceptor(sessionStore));
  dio.interceptors.add(_ErrorMappingInterceptor());

  return dio;
}

class _AuthInterceptor extends Interceptor {
  final SessionStore _sessions;
  _AuthInterceptor(this._sessions);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final session = await _sessions.load();
    if (session != null && session.token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer ${session.token}';
    }
    handler.next(options);
  }
}

class _ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final msgFromBody = _extractMessage(err.response?.data);
    final msg = msgFromBody ?? err.message ?? 'network error';
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: ApiException(statusCode: status, message: msg, cause: err),
        message: msg,
      ),
    );
  }

  String? _extractMessage(Object? body) {
    if (body is Map && body['error'] is String) {
      return body['error'] as String;
    }
    return null;
  }
}

extension DioErrorUnwrap on DioException {
  ApiException toApi() {
    final e = error;
    if (e is ApiException) return e;
    return ApiException(
      statusCode: response?.statusCode,
      message: message ?? 'network error',
      cause: this,
    );
  }
}
