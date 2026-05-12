import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/core/config/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('isComplete is true only with a non-empty URL', () {
      expect(const ServerConfig().isComplete, isFalse);
      expect(const ServerConfig(baseUrl: 'https://x:8080').isComplete, isTrue);
    });

    test('normalizes by stripping trailing slashes', () {
      final c = ServerConfig.normalize('https://example.com:8080///');
      expect(c.baseUrl, 'https://example.com:8080');
    });

    test('rejects URLs without http/https scheme', () {
      expect(() => ServerConfig.normalize('example.com'), throwsFormatException);
      expect(() => ServerConfig.normalize('ftp://example.com'), throwsFormatException);
    });

    test('normalize preserves allowSelfSigned flag', () {
      final c = ServerConfig.normalize('https://x/', allowSelfSigned: true);
      expect(c.allowSelfSigned, isTrue);
    });

    test('normalize trims surrounding whitespace', () {
      final c = ServerConfig.normalize('  https://x:8080  ');
      expect(c.baseUrl, 'https://x:8080');
    });
  });

  group('InMemoryServerConfigStore', () {
    test('reads back what was written', () async {
      final store = InMemoryServerConfigStore();
      expect(await store.load(), const ServerConfig());

      await store.save(const ServerConfig(baseUrl: 'https://x:8080', allowSelfSigned: true));
      final c = await store.load();
      expect(c.baseUrl, 'https://x:8080');
      expect(c.allowSelfSigned, isTrue);
    });

    test('clear empties the store', () async {
      final store = InMemoryServerConfigStore();
      await store.save(const ServerConfig(baseUrl: 'https://x'));
      await store.clear();
      expect((await store.load()).isComplete, isFalse);
    });
  });
}
