import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';

class LibraryRepository {
  final Dio _dio;
  LibraryRepository(this._dio);

  Future<LibraryResponse> library() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/library');
      return LibraryResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
