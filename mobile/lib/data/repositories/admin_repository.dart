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
}
