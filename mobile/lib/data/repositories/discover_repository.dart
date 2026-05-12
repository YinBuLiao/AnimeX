import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/bangumi_subject.dart';
import 'package:animex_mobile/data/dtos/mikan_schedule.dart';
import 'package:animex_mobile/data/dtos/search_result.dart';

class DiscoverRepository {
  final Dio _dio;
  DiscoverRepository(this._dio);

  Future<BangumiDiscoverPage> bangumiDiscover({
    int offset = 0,
    int limit = 24,
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/bangumi/discover',
        queryParameters: {'offset': offset, 'limit': limit},
      );
      return BangumiDiscoverPage.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<MikanSchedule> mikanSchedule() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/mikan/schedule');
      return MikanSchedule.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<SearchResponse> search(String query) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/search',
        queryParameters: {'q': query},
      );
      return SearchResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
