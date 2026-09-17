import 'package:beariscope/pages/picklists/picklist_presence.dart';
import 'package:material_ui/material_ui.dart';

class PicklistPresenceStack extends StatelessWidget {
  final PicklistPresence presence;
  const PicklistPresenceStack({super.key, required this.presence});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: presence.peers,
        builder: (context, peers, _) {
          if (peers.isEmpty) return const SizedBox.shrink();
          final visible = peers.take(4).toList();
          final count = visible.length + (peers.length > 4 ? 1 : 0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 32 + (count - 1) * 24,
              height: 36,
              child: Stack(
                children: [
                  for (var i = 0; i < count; i++)
                    Positioned(
                      left: i * 24,
                      top: 2,
                      child: Tooltip(
                        message: i < visible.length
                            ? visible[i]['name'] ?? 'Teammate'
                            : '${peers.length - 4} more online',
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            backgroundImage:
                                i < visible.length &&
                                    (visible[i]['avatarUrl'] as String?)
                                            ?.isNotEmpty ==
                                        true
                                ? NetworkImage(
                                    visible[i]['avatarUrl'] as String,
                                  )
                                : null,
                            onBackgroundImageError:
                                i < visible.length &&
                                    (visible[i]['avatarUrl'] as String?)
                                            ?.isNotEmpty ==
                                        true
                                ? (_, _) {}
                                : null,
                            child: i >= visible.length
                                ? Text(
                                    '+${peers.length - 4}',
                                    style: const TextStyle(fontSize: 10),
                                  )
                                : (visible[i]['avatarUrl'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                ? null
                                : Text(
                                    (visible[i]['name']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ??
                                            false)
                                        ? visible[i]['name']
                                              .toString()
                                              .trim()
                                              .characters
                                              .first
                                              .toUpperCase()
                                        : '?',
                                  ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
}
