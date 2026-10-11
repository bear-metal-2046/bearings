// TEMPORARY: Nexus debug tooling. See nexus_fixture.dart for removal steps.

import 'dart:convert';

import 'package:beariscope/pages/up_next/debug/nexus_fixture.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/services.dart';

/// Pass with `--dart-define=NEXUS_DEMO_EVENT_KEY=demoXXXX`.
const nexusDemoEventKey = String.fromEnvironment('NEXUS_DEMO_EVENT_KEY');

class _Probe {
  const _Probe({
    required this.eventKey,
    required this.elapsed,
    this.statusCode,
    this.error,
    this.raw,
    this.result,
  });

  final String eventKey;
  final Duration elapsed;
  final int? statusCode;
  final String? error;
  final Object? raw;
  final NexusFetchResult? result;
}

Future<_Probe> _probe(HoneycombClient client, String eventKey) async {
  final stopwatch = Stopwatch()..start();
  try {
    final raw = await client.get<dynamic>(
      '/events',
      queryParams: {'event': eventKey, 'enrich': 'true'},
      cachePolicy: CachePolicy.networkOnly,
    );
    return _Probe(
      eventKey: eventKey,
      elapsed: stopwatch.elapsed,
      statusCode: 200,
      raw: raw,
      result: parseNexusEventResponse(eventKey, raw),
    );
  } on HoneycombApiException catch (error) {
    debugPrint('Nexus debug: $eventKey HTTP ${error.statusCode}: $error');
    return _Probe(
      eventKey: eventKey,
      elapsed: stopwatch.elapsed,
      statusCode: error.statusCode,
      error: error.message,
    );
  } catch (error) {
    debugPrint('Nexus debug: $eventKey failed: $error');
    return _Probe(
      eventKey: eventKey,
      elapsed: stopwatch.elapsed,
      error: error.toString(),
    );
  }
}

class NexusDebugPage extends ConsumerStatefulWidget {
  const NexusDebugPage({super.key});

  @override
  ConsumerState<NexusDebugPage> createState() => _NexusDebugPageState();
}

class _NexusDebugPageState extends ConsumerState<NexusDebugPage> {
  late Future<List<_Probe>> _probes = _run();

  Future<List<_Probe>> _run() {
    final client = ref.read(honeycombClientProvider);
    return Future.wait([
      _probe(client, ref.read(currentEventProvider)),
      if (nexusDemoEventKey.isNotEmpty) _probe(client, nexusDemoEventKey),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final fixtureEnabled = ref.watch(nexusFixtureEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nexus Debug'),
        actions: [
          IconButton(
            tooltip: 'Run again',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => setState(() => _probes = _run()),
          ),
        ],
      ),
      body: FutureBuilder<List<_Probe>>(
        future: _probes,
        builder: (context, snapshot) {
          final probes = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: const Text('Use fixture for Up Next'),
                subtitle: const Text(
                  'Serve built-in sample Nexus data instead of Honeycomb',
                ),
                value: fixtureEnabled,
                onChanged: (value) =>
                    ref.read(nexusFixtureEnabledProvider.notifier).set(value),
              ),
              if (nexusDemoEventKey.isEmpty)
                const ListTile(
                  title: Text('No demo event key'),
                  subtitle: Text(
                    'Run with --dart-define=NEXUS_DEMO_EVENT_KEY=<key> to also '
                    'request the Nexus demo event.',
                  ),
                ),
              if (probes == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                for (final probe in probes) _ProbeCard(probe: probe),
            ],
          );
        },
      ),
    );
  }
}

class _ProbeCard extends StatelessWidget {
  const _ProbeCard({required this.probe});

  final _Probe probe;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final result = probe.result;
    final status = switch (result) {
      NexusAvailable(:final status) => status,
      NexusEmpty(:final status) => status,
      _ => null,
    };

    final lines = <String>[
      'HTTP ${probe.statusCode ?? '-'} in ${probe.elapsed.inMilliseconds} ms',
      if (probe.error != null) 'Error: ${probe.error}',
      if (result != null) 'Result: ${result.runtimeType}',
      if (result?.problem != null) 'Problem: ${result!.problem}',
      if (status != null) ...[
        'Matches: ${status.matches.length}',
        'Announcements: ${status.announcements.length}',
        'Now queuing: ${status.nowQueuing ?? '-'}',
        'Data as of: ${status.dataAsOfTime?.toLocal() ?? '-'}',
        for (final warning in status.parseWarnings) 'Warning: $warning',
      ],
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(probe.eventKey, style: textTheme.titleMedium),
            for (final line in lines) SelectableText(line),
            if (probe.raw != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Raw JSON'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(probe.raw),
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
