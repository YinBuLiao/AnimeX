import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';

class SubscriptionRepository {
  final Dio _dio;
  SubscriptionRepository(this._dio);

  /// POST /api/mikan/subscribe. The backend requires Mikan credentials to be
  /// configured server-side; failure surfaces as ApiException with the
  /// server's Chinese message.
  Future<void> subscribe({
    required String title,
    int? subjectId,
    String? coverUrl,
    String? summary,
    int language = 0,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/mikan/subscribe',
        data: {
          if (subjectId != null) 'subject_id': subjectId,
          'title': title,
          if (coverUrl != null) 'cover_url': coverUrl,
          if (summary != null) 'summary': summary,
          'language': language,
        },
      );
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  /// GET /api/subscriptions. Returns the bangumi titles currently flagged
  /// subscribed on the server. Used to hydrate the local mirror.
  Future<List<String>> listSubscribedTitles() async {
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('/api/subscriptions');
      final list =
          (resp.data?['titles'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList();
      return list;
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
