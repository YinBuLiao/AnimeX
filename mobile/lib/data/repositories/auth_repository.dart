import 'package:dio/dio.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/app_user.dart';
import 'package:animex_mobile/data/dtos/login_response.dart';

class AuthRepository {
  final Dio _dio;
  final SessionStore _sessions;
  AuthRepository({required Dio dio, required SessionStore sessions})
      : _dio = dio,
        _sessions = sessions;

  Future<AppUser> login(String username, String password) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/api/auth/mobile-login',
        data: {'username': username, 'password': password},
      );
      final parsed = LoginResponse.fromJson(resp.data ?? const {});
      await _sessions.save(StoredSession(
        token: parsed.token,
        username: parsed.user.username,
        role: parsed.user.role,
        expiresAtSec: parsed.expiresAtSec,
      ));
      return parsed.user;
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<AppUser> me() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/auth/me');
      return AppUser.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  /// POST /api/auth/password. Server clears the session cookie after a
  /// successful change so the caller is expected to re-login.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/auth/password',
        data: {
          'old_password': oldPassword,
          'new_password': newPassword,
          'confirm_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout');
    } catch (_) {
      // best-effort; clear local state regardless
    }
    await _sessions.clear();
  }
}
