import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:ui/widgets/bearings_modal.dart';

extension on GroveConnectionState {
  String get label => switch (this) {
    GroveConnectionState.connected => 'Connected',
    GroveConnectionState.connecting => 'Connecting…',
    GroveConnectionState.reconnecting => 'Reconnecting…',
    GroveConnectionState.disconnected => 'Offline',
    GroveConnectionState.signInRequired => 'Sign-in required',
  };

  IconData get icon => switch (this) {
    GroveConnectionState.connected => LucideIcons.cloud,
    GroveConnectionState.connecting ||
    GroveConnectionState.reconnecting => LucideIcons.loaderCircle,
    GroveConnectionState.disconnected => LucideIcons.cloudOff,
    GroveConnectionState.signInRequired => LucideIcons.lock,
  };
}

class ServerConnectionButton extends ConsumerWidget {
  const ServerConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(honeycombConnectionProvider).value ??
        GroveConnectionState.connecting;
    return IconButton(
      tooltip: state.label,
      icon: Icon(state.icon, size: 18),
      onPressed: () => BearingsModal.show<void>(
        context,
        builder: (_) => const _ServerConnectionModal(),
      ),
    );
  }
}

class _ServerConnectionModal extends ConsumerWidget {
  const _ServerConnectionModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(honeycombConnectionProvider).value;
    final details = ref.watch(honeycombConnectionInfoProvider).value;
    final endpoint = ref.watch(honeycombEndpointPreferenceProvider).baseUrl;
    final reply = details?.lastReplyAt?.toLocal();
    final lastReply = reply == null
        ? 'No reply yet'
        : '${MaterialLocalizations.of(context).formatShortDate(reply)} · '
              '${TimeOfDay.fromDateTime(reply).format(context)}';

    return BearingsModal(
      title: 'Server connection',
      actions: const [],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Status'),
            subtitle: Text(
              (details?.state ?? state ?? GroveConnectionState.connecting)
                  .label,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Server URL'),
            subtitle: SelectableText(endpoint),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Last reply'),
            subtitle: Text(lastReply),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Last failure'),
            subtitle: Text(details?.lastFailure?.message ?? 'None recorded'),
          ),
        ],
      ),
    );
  }
}
