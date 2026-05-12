import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

class AdminRepository {
  final Dio _dio;
  AdminRepository(this._dio);

  Future<AdminOverview> overview() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/admin/overview');
      return AdminOverview.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<AdminMonitor> monitor() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/admin/monitor');
      return AdminMonitor.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<List<AdminLogEntry>> logs() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/admin/logs');
      final list = (resp.data?['logs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminLogEntry.fromJson)
          .toList();
      return list;
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<List<AdminDownloadRequest>> downloadRequests() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
          '/api/admin/download-requests');
      final list = (resp.data?['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminDownloadRequest.fromJson)
          .toList();
      return list;
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  /// Approves or rejects a download request. Returns the refreshed list.
  Future<List<AdminDownloadRequest>> actOnDownloadRequest({
    required int id,
    required String action, // 'approve' or 'reject'
  }) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/api/admin/download-requests',
        data: {'id': id, 'action': action},
      );
      final list = (resp.data?['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminDownloadRequest.fromJson)
          .toList();
      return list;
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<List<AdminUser>> listUsers() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/users');
      return (resp.data?['users'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList();
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  /// Creates or updates a user. role is 'admin' or 'user'. Password is
  /// required for new users; for existing users it overwrites if non-empty.
  Future<void> saveUser({
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/users',
        data: {
          'username': username,
          'password': password,
          'role': role,
        },
      );
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<List<AdminInviteCode>> listInviteCodes() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
          '/api/admin/invite-codes');
      return (resp.data?['codes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminInviteCode.fromJson)
          .toList();
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<List<AdminInviteCode>> generateInviteCodes({
    int count = 1,
    String? expiresAt,
  }) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/api/admin/invite-codes',
        data: {
          'count': count,
          if (expiresAt != null && expiresAt.isNotEmpty)
            'expires_at': expiresAt,
        },
      );
      return (resp.data?['codes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminInviteCode.fromJson)
          .toList();
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<List<AdminInviteCode>> deleteInviteCodes(List<String> codes) async {
    try {
      final resp = await _dio.delete<Map<String, dynamic>>(
        '/api/admin/invite-codes',
        data: {'codes': codes},
      );
      return (resp.data?['codes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminInviteCode.fromJson)
          .toList();
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<List<AdminAnimeItem>> listAnime() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/admin/anime');
      return (resp.data?['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminAnimeItem.fromJson)
          .toList();
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  /// Bulk-deletes bangumi by title. When deleteFiles is true the backend
  /// also tries to remove the underlying storage. Returns true on success.
  Future<int> deleteAnime({
    required List<String> titles,
    bool deleteFiles = false,
  }) async {
    try {
      final resp = await _dio.delete<Map<String, dynamic>>(
        '/api/admin/anime',
        data: {
          'titles': titles,
          'delete_files': deleteFiles,
        },
      );
      return (resp.data?['deleted'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<Map<String, dynamic>> getSystemConfig() async {
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('/api/admin/config');
      return Map<String, dynamic>.from(
          (resp.data?['config'] as Map?) ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<Map<String, dynamic>> saveSystemConfig(
      Map<String, dynamic> patch) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/api/admin/config',
        data: patch,
      );
      return Map<String, dynamic>.from(
          (resp.data?['config'] as Map?) ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
