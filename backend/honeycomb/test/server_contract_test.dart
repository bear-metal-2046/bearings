import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:honeycomb/src/picklists.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../routes/api/[...path].dart' as api;
import '../routes/health.dart' as health;

class _Context extends Mock implements RequestContext {}

void main() {
  test('health is available without a database connection', () async {
    final response = health.onRequest(_Context());
    expect(response.statusCode, 200);
    expect(jsonDecode(await response.body()), {'status': 'ok'});
  });

  test(
    'legacy Easy Auth principal headers do not authenticate requests',
    () async {
      final context = _Context();
      when(() => context.request).thenReturn(
        Request.get(
          Uri.parse('http://localhost:8080/api/auth/me'),
          headers: {'x-ms-client-principal-id': 'admin'},
        ),
      );
      final response = await api.onRequest(context, 'auth/me');
      expect(response.statusCode, 401);
    },
  );

  test('realtime socket rejects an unsigned ticket', () async {
    final context = _Context();
    when(() => context.request).thenReturn(
      Request.get(
        Uri.parse('http://localhost:8080/api/picklists/realtime?ticket=forged'),
      ),
    );
    final response = await api.onRequest(context, 'picklists/realtime');
    expect(response.statusCode, 401);
  });

  test('picklist input bounds reject oversized and empty fields', () {
    expect(bounded('  title  ', 20), 'title');
    expect(bounded(' ', 20), isNull);
    expect(bounded('x' * 129, 128), isNull);
    expect(teamKeyList(['frc1', 'frc1', 'frc2']), ['frc1', 'frc2']);
    expect(teamKeyList(['']), isNull);
    expect(teamKeyList(List.filled(501, 'frc1')), isNull);
  });
}
