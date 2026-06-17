import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('core exports', () {
    test('device enums are available', () {
      expect(DeviceOS.values, isNotEmpty);
      expect(DevicePlatform.values, isNotEmpty);
    });

    test('cache policy enum is available', () {
      expect(CachePolicy.values, contains(CachePolicy.networkFirst));
    });
  });
}
