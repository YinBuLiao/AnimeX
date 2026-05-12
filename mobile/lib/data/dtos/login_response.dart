import 'package:animex_mobile/data/dtos/app_user.dart';

class LoginResponse {
  final String token;
  final int expiresAtSec;
  final AppUser user;

  const LoginResponse({
    required this.token,
    required this.expiresAtSec,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> j) => LoginResponse(
        token: (j['token'] as String?) ?? '',
        expiresAtSec: (j['expires_at'] as num?)?.toInt() ?? 0,
        user: AppUser.fromJson(j),
      );
}
