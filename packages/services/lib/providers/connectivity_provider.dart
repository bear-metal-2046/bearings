import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'connectivity_provider.g.dart';

const _primaryHoneycombUrl = String.fromEnvironment(
  'HONEYCOMB_URL',
  defaultValue: 'https://bearings-honeycomb.westus2.cloudapp.azure.com',
);

String _apiUrl(String url) {
  final base = url.trim().replaceFirst(RegExp(r'/+$'), '');
  return base.endsWith('/api') ? base : '$base/api';
}

enum HoneycombEndpointMode { azure, cloudflare, custom }

class HoneycombEndpointSelection {
  final HoneycombEndpointMode mode;
  final String? customUrl;

  const HoneycombEndpointSelection({required this.mode, this.customUrl});

  const HoneycombEndpointSelection.azure()
    : mode = HoneycombEndpointMode.azure,
      customUrl = null;

  String get baseUrl {
    switch (mode) {
      case HoneycombEndpointMode.azure:
        return _apiUrl(_primaryHoneycombUrl);
      case HoneycombEndpointMode.cloudflare:
        return 'https://honeycomb.bearings.workers.dev/api';
      case HoneycombEndpointMode.custom:
        final url = customUrl?.trim();
        if (url == null || url.isEmpty) {
          // fallback to azure if custom is invalid
          return _apiUrl(_primaryHoneycombUrl);
        }
        return _apiUrl(url);
    }
  }
}

const _endpointModeKey = 'honeycomb_endpoint_mode';
const _endpointCustomUrlKey = 'honeycomb_endpoint_custom_url';

@Riverpod(keepAlive: true)
class HoneycombEndpointPreference extends _$HoneycombEndpointPreference {
  @override
  HoneycombEndpointSelection build() {
    // Synchronously return default, then async load will update
    return const HoneycombEndpointSelection.azure();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_endpointModeKey);
    final mode = HoneycombEndpointMode.values
        .cast<HoneycombEndpointMode?>()
        .firstWhere((entry) => entry?.name == modeName, orElse: () => null);

    if (mode != null) {
      state = HoneycombEndpointSelection(
        mode: mode,
        customUrl: prefs.getString(_endpointCustomUrlKey),
      );
    }
  }

  Future<void> setSelection(
    HoneycombEndpointMode mode, {
    String? customUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointModeKey, mode.name);

    if (customUrl != null && customUrl.trim().isNotEmpty) {
      await prefs.setString(_endpointCustomUrlKey, customUrl.trim());
    } else {
      await prefs.remove(_endpointCustomUrlKey);
    }

    state = HoneycombEndpointSelection(
      mode: mode,
      customUrl: customUrl?.trim(),
    );
  }

  Future<void> setBest() => setSelection(HoneycombEndpointMode.azure);

  Future<void> setAzure() => setSelection(HoneycombEndpointMode.azure);

  Future<void> setCloudflare() =>
      setSelection(HoneycombEndpointMode.cloudflare);

  Future<void> setCustomUrl(String? value) {
    return setSelection(HoneycombEndpointMode.custom, customUrl: value);
  }
}
