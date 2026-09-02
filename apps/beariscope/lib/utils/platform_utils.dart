import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

class PlatformUtils {
  static bool isMobile() {
    return Platform.isAndroid || Platform.isIOS;
  }

  static bool isDesktop() {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  static bool isWeb() {
    return kIsWeb;
  }

  static bool useDesktopUI(BuildContext context) {
    return isDesktop() &&
        (!isMobile() && MediaQuery.of(context).size.width >= 500) &&
        MediaQuery.of(context).size.height >= 400;
  }
}
