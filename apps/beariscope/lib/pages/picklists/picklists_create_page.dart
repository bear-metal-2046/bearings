import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class PicklistsCreatePage extends StatefulWidget {
  const PicklistsCreatePage({super.key});

  @override
  State<PicklistsCreatePage> createState() => _PicklistsCreatePageState();
}

class _PicklistsCreatePageState extends State<PicklistsCreatePage> {
  // Tracks creation mode: 'scratch' or 'order'
  String _selectedMethod = 'scratch';
  final TextEditingController _teamCountController = TextEditingController(
    text: '24',
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _teamCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Picklist')),
      body: Center(
        child: Container(
          // Constrains width nicely on large web/desktop layouts
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'How would you like to start?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),

                // Option 1: From Scratch Card
                Card(
                  elevation: _selectedMethod == 'scratch' ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _selectedMethod == 'scratch'
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _selectedMethod = 'scratch'),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(LucideIcons.filePlus, size: 32),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Start from scratch',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Get a blank canvas picklist to build completely on your own.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Option 2: From Order Card
                Card(
                  elevation: _selectedMethod == 'order' ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _selectedMethod == 'order'
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _selectedMethod = 'order'),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(LucideIcons.sparkles, size: 32),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Start from rankings order',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Pre-populate your template using the highest ranking point earners.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Conditional configuration inputs if "Start from order" is active
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selectedMethod == 'order'
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          key: const ValueKey('order_inputs'),
                          children: [
                            Text(
                              'Rankings Settings',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _teamCountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Number of teams to pull (X)',
                                helperText:
                                    'Pulls top teams sorted by total points',
                                prefixIcon: Icon(LucideIcons.users),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a number';
                                }
                                if (int.tryParse(value) == null) {
                                  return 'Must be a valid number';
                                }
                                return null;
                              },
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                const Spacer(),

                // Form action controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          // POC complete execution context placeholder
                          context.pop();
                        }
                      },
                      child: const Text('Create Picklist'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
