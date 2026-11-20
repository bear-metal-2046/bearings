import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../routes/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  test('GET / reports Honeycomb process health', () async {
    final response = route.onRequest(_MockRequestContext());
    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(await response.body()), {
      'service': 'honeycomb',
      'status': 'ok',
    });
  });
}
