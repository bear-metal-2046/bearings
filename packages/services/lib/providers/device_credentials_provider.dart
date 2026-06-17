import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/api_provider.dart';

part 'device_credentials_provider.g.dart';

class DeviceCredentials {
  final String clientId;
  final String clientSecret;
  final String domain;
  final String audience;

  const DeviceCredentials({
    required this.clientId,
    required this.clientSecret,
    required this.domain,
    required this.audience,
  });

  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      'clientSecret': clientSecret,
      'domain': domain,
      'audience': audience,
    };
  }

  factory DeviceCredentials.fromJson(Map<String, dynamic> json) {
    return DeviceCredentials(
      clientId: json['clientId'] as String,
      clientSecret: json['clientSecret'] as String,
      domain: json['domain'] as String,
      audience: json['audience'] as String,
    );
  }

  String toQrPayload() {
    return base64Encode(utf8.encode(jsonEncode(toJson())));
  }
}

Map<String, dynamic> decodeProvisioningPayload(String raw) {
  final trimmed = raw.trim();

  try {
    final payload = jsonDecode(trimmed);
    if (payload is Map<String, dynamic>) {
      return payload;
    }
  } on FormatException {
    // Fall through to base64 decoding.
  }

  final decoded = utf8.decode(base64Decode(trimmed));
  final payload = jsonDecode(decoded);
  if (payload is Map<String, dynamic>) {
    return payload;
  }

  throw const FormatException('Invalid provisioning payload');
}

@Riverpod(keepAlive: false)
Future<DeviceCredentials> deviceCredentials(Ref ref) async {
  final client = ref.watch(honeycombClientProvider);
  final payload = await client.get<Map<String, dynamic>>(
    '/device/credentials',
    cachePolicy: CachePolicy.networkFirst,
  );
  return DeviceCredentials.fromJson(payload);
}
