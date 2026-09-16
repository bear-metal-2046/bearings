import 'package:material_ui/material_ui.dart';
import 'package:beariscope/widgets/beariscope_search_bar.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class UtilitiesPage extends StatefulWidget {
  const UtilitiesPage({super.key});

  @override
  State<UtilitiesPage> createState() => _UtilitiesPageState();
}

class _UtilitiesPageState extends State<UtilitiesPage> {
  final TextEditingController _searchTermTEC = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchTermTEC.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 8.0,
        title: BeariscopeSearchBar(
          controller: _searchTermTEC,
          focusNode: _searchFocusNode,
          hintText: 'Search...',
        ),
        actions: [SizedBox(width: 48)],
      ),
      body: const BeariscopeStatusView(
        icon: LucideIcons.wrench,
        title: 'No utilities available',
        subtitle: 'There are no utilities to display.',
      ),
    );
  }
}
