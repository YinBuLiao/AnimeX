import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/data/dtos/app_user.dart';
import 'package:animex_mobile/data/dtos/health_info.dart';
import 'package:animex_mobile/data/dtos/login_response.dart';

void main() {
  test('HealthInfo.fromJson parses backend payload', () {
    final h = HealthInfo.fromJson({
      'ok': true,
      'version': 'v0.2.0',
      'installed': true,
      'require_login': false,
    });
    expect(h.version, 'v0.2.0');
    expect(h.installed, isTrue);
    expect(h.requireLogin, isFalse);
  });

  test('HealthInfo.fromJson tolerates missing fields', () {
    final h = HealthInfo.fromJson(const {});
    expect(h.version, '');
    expect(h.installed, isFalse);
    expect(h.requireLogin, isTrue);
  });

  test('AppUser.fromJson parses /api/auth/me payload', () {
    final u =
        AppUser.fromJson({'ok': true, 'username': 'alice', 'role': 'admin'});
    expect(u.username, 'alice');
    expect(u.role, 'admin');
    expect(u.isAdmin, isTrue);
  });

  test('AppUser.isAdmin is false for non-admin role', () {
    final u = AppUser.fromJson({'username': 'bob', 'role': 'user'});
    expect(u.isAdmin, isFalse);
  });

  test('LoginResponse.fromJson parses mobile-login payload', () {
    final r = LoginResponse.fromJson({
      'ok': true,
      'token': 'tok',
      'expires_at': 1700000000,
      'username': 'bob',
      'role': 'user',
    });
    expect(r.token, 'tok');
    expect(r.expiresAtSec, 1700000000);
    expect(r.user.username, 'bob');
    expect(r.user.role, 'user');
  });
}
