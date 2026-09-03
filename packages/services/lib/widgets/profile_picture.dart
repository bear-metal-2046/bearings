import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/user_profile_provider.dart';

class ProfilePicture extends ConsumerWidget {
  final double size;
  final String? fallbackText;

  const ProfilePicture({super.key, this.size = 16, this.fallbackText});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncUser = ref.watch(userInfoProvider);

    return asyncUser.when(
      loading: () => SizedBox(
        width: size * 2,
        height: size * 2,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (err, stack) => CircleAvatar(
        radius: size,
        backgroundColor: Theme.of(context).colorScheme.error,
        child: Icon(
          LucideIcons.circleAlert,
          size: size,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      data: (user) {
        final Uint8List? photo = user?.photo;
        if (photo != null) {
          return CircleAvatar(
            radius: size,
            backgroundImage: MemoryImage(photo),
          );
        }

        final display =
            fallbackText ??
            (user?.name?.trim().isNotEmpty == true
                ? user!.name!.characters.first.toUpperCase()
                : '?');

        return CircleAvatar(
          radius: size,
          child: Text(
            display,
            style: TextStyle(fontSize: size * 0.9, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}
