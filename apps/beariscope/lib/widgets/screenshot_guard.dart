import 'dart:async';

import 'package:beariscope/utils/platform_utils_stub.dart'
    if (dart.library.io) 'package:beariscope/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:screen_protector/screen_protector.dart';

/// Blocks screenshots and screen recordings on Android and iOS while mounted.
///
/// Uses a process-wide reference count so nested guarded routes (for example
/// Picklists list -> editor) do not turn protection off when the new page
/// initializes before the previous page disposes. No-ops on web and desktop.
class ScreenshotGuard extends StatefulWidget {
  final Widget child;

  const ScreenshotGuard({super.key, required this.child});

  @override
  State<ScreenshotGuard> createState() => _ScreenshotGuardState();
}

class _ScreenshotGuardState extends State<ScreenshotGuard> {
  static int _activeGuards = 0;

  @override
  void initState() {
    super.initState();
    _activeGuards++;
    if (_activeGuards == 1) {
      unawaited(_setProtectionEnabled(true));
    }
  }

  @override
  void dispose() {
    _activeGuards--;
    if (_activeGuards == 0) {
      unawaited(_setProtectionEnabled(false));
    }
    super.dispose();
  }

  static bool get _supportedPlatform {
    return !kIsWeb && PlatformUtils.isMobile();
  }

  static Future<void> _setProtectionEnabled(bool enabled) async {
    if (!_supportedPlatform) return;
    if (enabled) {
      await ScreenProtector.preventScreenshotOn();
    } else {
      await ScreenProtector.preventScreenshotOff();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
