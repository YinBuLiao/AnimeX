import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/core/auth/session_store.dart';

void main() {
  test('InMemorySessionStore round-trips a session', () async {
    final s = InMemorySessionStore();
    expect(await s.load(), isNull);

    await s.save(const StoredSession(
      token: 'abc',
      username: 'alice',
      role: 'admin',
      expiresAtSec: 1234567890,
    ));
    final got = await s.load();
    expect(got?.token, 'abc');
    expect(got?.username, 'alice');
    expect(got?.role, 'admin');
    expect(got?.expiresAtSec, 1234567890);
  });

  test('clear removes the session', () async {
    final s = InMemorySessionStore();
    await s.save(const StoredSession(
      token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    await s.clear();
    expect(await s.load(), isNull);
  });

  test('StoredSession toJson / fromJson round-trips', () {
    const s = StoredSession(
      token: 't', username: 'u', role: 'admin', expiresAtSec: 99);
    final back = StoredSession.fromJson(s.toJson());
    expect(back.token, s.token);
    expect(back.username, s.username);
    expect(back.role, s.role);
    expect(back.expiresAtSec, s.expiresAtSec);
  });
}
