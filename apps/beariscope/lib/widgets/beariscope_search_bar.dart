import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Centers a search field across the full app-bar toolbar.
class BeariscopeCenteredAppBarSearch extends StatelessWidget {
  final Widget searchBar;

  const BeariscopeCenteredAppBarSearch({super.key, required this.searchBar});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      left: false,
      right: false,
      child: SizedBox(
        height: kToolbarHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth - 240;
            final searchWidth = availableWidth < 720 ? availableWidth : 720.0;

            return Center(
              child: SizedBox(width: searchWidth, child: searchBar),
            );
          },
        ),
      ),
    );
  }
}

/// The standard search field used by searchable Beariscope pages.
class BeariscopeSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;

  const BeariscopeSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 0) {
          FocusScope.of(context).unfocus();
        }
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return SearchBar(
            focusNode: focusNode,
            controller: controller,
            hintText: hintText,
            elevation: WidgetStateProperty.all(8.0),
            padding: const WidgetStatePropertyAll<EdgeInsets>(
              EdgeInsets.symmetric(horizontal: 16.0),
            ),
            leading: const Icon(LucideIcons.search),
            trailing: value.text.isNotEmpty
                ? [
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(LucideIcons.x),
                      onPressed: controller.clear,
                    ),
                  ]
                : null,
          );
        },
      ),
    );
  }
}
