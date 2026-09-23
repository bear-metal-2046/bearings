import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) => (context) async {
  final request = context.request;
  final origin = request.headers['origin'];
  final allowed = (Platform.environment['CORS_ALLOWED_ORIGINS'] ?? '')
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
  final accepted = origin != null && allowed.contains(origin);
  if (request.headers['upgrade']?.toLowerCase() == 'websocket' &&
      origin != null &&
      !accepted) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Origin not allowed'},
    );
  }
  final cors = accepted
      ? <String, Object>{
          'access-control-allow-origin': origin,
          'vary': 'Origin',
          'access-control-allow-methods':
              'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'access-control-allow-headers':
              'authorization, content-type, x-api-key',
          'access-control-max-age': '600',
        }
      : <String, Object>{};
  if (request.method == HttpMethod.options) {
    return Response(statusCode: 204, headers: cors);
  }
  final response = await handler(context);
  return cors.isEmpty
      ? response
      : response.copyWith(
          headers: {...response.headers, ...cors},
        );
};
