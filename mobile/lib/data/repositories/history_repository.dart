import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/history_entry.dart';

class HistoryRepository {
  final Dio _dio;
  HistoryRepository(this._dio);

  Future<HistoryResponse> list() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/history');
      return HistoryResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<HistoryResponse> report(HistoryEntry entry) async {
    try {
      final resp = await _dio.put<Map<String, dynamic>>(
        '/api/history',
        data: entry.toJson(),
      );
      return HistoryResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<void> clearAll() async {
    try {
      await _dio.delete<Map<String, dynamic>>('/api/history');
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<HistoryResponse> remove(String fileId) async {
    try {
      final resp = await _dio.delete<Map<String, dynamic>>(
        '/api/history',
        queryParameters: {'file_id': fileId},
      );
      return HistoryResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
