import 'package:material_ui/material_ui.dart';
import 'package:beariscope/widgets/beariscope_search_bar.dart';

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
      body: Center(
        child: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16)),
        ),
      ),
    );
  }
}
