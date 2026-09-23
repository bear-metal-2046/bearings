import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class Auth0Management {
  Auth0Management._();
  static final instance = Auth0Management._();

  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  String get domain {
    final value = Platform.environment['AUTH0_DOMAIN'];
    if (value == null || value.isEmpty)
      throw StateError('AUTH0_DOMAIN is required');
    return value;
  }

  Future<String> _managementToken() async {
    if (_token != null && DateTime.now().isBefore(_expires)) return _token!;
    final env = Platform.environment;
    final response = await http
        .post(
          Uri.https(domain, '/oauth/token'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'client_id': env['AUTH0_M2M_CLIENT_ID'],
            'client_secret': env['AUTH0_M2M_CLIENT_SECRET'],
            'audience': env['AUTH0_M2M_AUDIENCE'],
            'grant_type': 'client_credentials',
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200)
      throw StateError('Auth0 management token failed');
    final data = jsonDecode(response.body) as Map;
    _token = data['access_token'] as String;
    _expires = DateTime.now().add(
      Duration(
        seconds: ((data['expires_in'] as num).toInt() - 30).clamp(1, 86400),
      ),
    );
    return _token!;
  }

  Future<dynamic> call(String method, String path, [Object? body]) async {
    final token = await _managementToken();
    final request = http.Request(method, Uri.parse('https://$domain$path'));
    request.headers.addAll({
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final client = http.Client();
    late final http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 10)),
      );
    } finally {
      client.close();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Auth0 management request failed: ' + response.statusCode.toString(),
      );
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<dynamic> user(String id) =>
      call('GET', '/api/v2/users/' + Uri.encodeComponent(id));

  Future<dynamic> updateUser(String id, Map<String, dynamic> changes) =>
      call('PATCH', '/api/v2/users/' + Uri.encodeComponent(id), changes);

  Future<List<dynamic>> users() async {
    final result = await call(
      'GET',
      '/api/v2/users?fields=user_id,username,nickname,name,email,picture&include_fields=true&per_page=100',
    );
    return result as List;
  }
}
