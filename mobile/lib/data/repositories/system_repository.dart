import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/health_info.dart';

class SystemRepository {
  final Dio _dio;
  SystemRepository(this._dio);

  Future<HealthInfo> health() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/health');
      return HealthInfo.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
