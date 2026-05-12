import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/notification_entry.dart';

class NotificationsRepository {
  final Dio _dio;
  NotificationsRepository(this._dio);

  /// Lists notifications. When [since] is non-null only entries with
  /// created_at strictly greater than the unix timestamp are returned.
  Future<NotificationsResponse> list({int? since}) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/notifications',
        queryParameters: since != null ? {'since': since} : null,
      );
      return NotificationsResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<void> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/devices/register',
        data: {'fcm_token': fcmToken, 'platform': platform},
      );
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<void> unregisterDevice(String fcmToken) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/devices/unregister',
        data: {'fcm_token': fcmToken},
      );
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
