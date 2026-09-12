import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final eventKey = context.request.uri.queryParameters['event']?.trim();
  if (eventKey == null || eventKey.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Missing event query parameter'},
    );
  }

  final apiKey = Platform.environment['NEXUS_API_KEY']?.trim();
  if (apiKey == null || apiKey.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {'error': 'Nexus API key is not configured'},
    );
  }

  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('https://frc.nexus/api/v1/event/$eventKey'),
    );
    request.headers.set('Nexus-Api-Key', apiKey);
    request.headers.set('Accept', 'application/json');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != HttpStatus.ok) {
      return Response(
        statusCode: response.statusCode,
        body: body,
        headers: {'content-type': 'application/json'},
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'Unexpected Nexus response shape'},
      );
    }

    return Response.json(body: decoded);
  } on SocketException {
    return Response.json(
      statusCode: HttpStatus.badGateway,
      body: {'error': 'Unable to reach Nexus'},
    );
  } on FormatException {
    return Response.json(
      statusCode: HttpStatus.badGateway,
      body: {'error': 'Invalid Nexus response'},
    );
  } finally {
    client.close(force: true);
  }
}
