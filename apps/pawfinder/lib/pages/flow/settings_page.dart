import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:pawfinder/data/local_data.dart';
import 'package:pawfinder/providers/app_provider.dart';
import 'package:pawfinder/services/device_auth_service.dart';

const String _signOutPassword = 'johnscout2046';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = ref.watch(brightnessNotifierProvider);
    final colorScheme = ref.watch(colorSchemeNotifierProvider);
    final isDarkMode = brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            context.pop();
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isDarkMode ? Icons.dark_mode : Icons.light_mode,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Theme',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isDarkMode
                                  ? 'Dark theme is currently active'
                                  : 'Light theme is currently active',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: isDarkMode,
                        onChanged: (value) {
                          ref
                              .read(brightnessNotifierProvider.notifier)
                              .changeBrightness(value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Color Scheme',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AppColorScheme>(
                    initialValue: colorScheme,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: AppColorScheme.values
                        .map(
                          (scheme) => DropdownMenuItem<AppColorScheme>(
                            value: scheme,
                            child: Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: scheme.seedColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(scheme.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (scheme) {
                      if (scheme == null) return;
                      ref
                          .read(colorSchemeNotifierProvider.notifier)
                          .changeColorScheme(scheme);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Deprovision Device'),
            subtitle: const Text('Remove stored credentials from this device'),
            onTap: () => _showPasswordDialog(
              context,
              ref,
              () => _showDeprovisionDialog(context, ref),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete Local Data'),
            subtitle: const Text(
              'Clears all cached match data from this device',
            ),
            onTap: () => _showPasswordDialog(
              context,
              ref,
              () => _showDeleteCacheDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPasswordDialog(
    BuildContext context,
    WidgetRef ref,
    Function redirect,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const _PasswordDialog(),
    );

    if (result == true && context.mounted) {
      redirect();
    }
  }

  Future<void> _showDeleteCacheDialog(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Local Data'),
        content: const Text(
          'This will delete all locally stored match data, schedule cache, and upload queue. your config (event/position) will be kept.\n\nYou should upload pending matches first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete ?? false) {
      await Hive.box(boxKey).clear();
    }
  }

  Future<void> _showDeprovisionDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final shouldDeprovision = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deprovision Device'),
        content: const Text(
          'This will remove all stored credentials from this device. You will need to scan a new QR code from Beariscope to use Pawfinder again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Deprovision',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDeprovision ?? false) {
      final auth = await ref.read(deviceAuthServiceProvider.future);
      await auth.deprovision();
      if (context.mounted) {
        context.go('/provision');
      }
    }
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _verify() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_passwordController.text == _signOutPassword) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMessage = 'Incorrect password';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                errorText: _errorMessage,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                return null;
              },
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage = null;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _verify, child: const Text('Verify')),
      ],
    );
  }
}
