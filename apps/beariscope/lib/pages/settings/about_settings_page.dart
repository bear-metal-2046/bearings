import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/widgets/settings_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:services/release/release_info.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutSettingsPage extends ConsumerWidget {
  const AboutSettingsPage({super.key});

  Future<void> _launchUrl(BuildContext context, Uri uri, String label) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $label')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          SettingsGroup(
            title: 'App',
            children: [
              ListTile(
                title: const Text('Version'),
                trailing: FutureBuilder<(PackageInfo, String)>(
                  future:
                      Future.wait([
                        PackageInfo.fromPlatform(),
                        loadReleaseCodename(),
                      ]).then(
                        (results) => (
                          results[0] as PackageInfo,
                          (results[1] as String).trim(),
                        ),
                      ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text('Loading');
                    } else if (snapshot.hasError) {
                      return const Text('Error');
                    } else {
                      final (info, codename) = snapshot.data!;
                      final version = info.version;
                      if (codename.isEmpty || codename == 'Unknown') {
                        return Text(version);
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [Text('$version $codename')],
                      );
                    }
                  },
                ),
              ),
              ListTile(
                title: const Text('Beariscope GitHub'),
                subtitle: const Text('Source code & other downloads'),
                trailing: const Icon(Symbols.open_in_new_rounded),
                onTap: () => _launchUrl(
                  context,
                  Uri.parse('https://github.com/bear-metal-2046/bearings'),
                  'Beariscope GitHub',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsGroup(
            title: 'Data Sources',
            children: [
              ListTile(
                title: const Text('The Blue Alliance'),
                subtitle: const Text('Match schedule & team data'),
                trailing: const Icon(Symbols.open_in_new_rounded),
                onTap: () {
                  _launchUrl(
                    context,
                    ref.tbaWebsiteUri('/'),
                    'The Blue Alliance',
                  );
                },
              ),
              ListTile(
                title: const Text('FRC Nexus'),
                subtitle: const Text('Event pit & queue information'),
                trailing: const Icon(Symbols.open_in_new_rounded),
                onTap: () => _launchUrl(
                  context,
                  Uri.parse('https://frc.nexus'),
                  'FRC Nexus',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsGroup(
            title: 'Legal',
            children: [
              ListTile(
                title: const Text('Privacy Policy'),
                trailing: const Icon(Symbols.open_in_new_rounded),
                onTap: () => _launchUrl(
                  context,
                  Uri.parse(
                    'https://bear-metal-apps.github.io/beariscope/privacy-policy',
                  ),
                  'Privacy Policy',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
