import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pawfinder/custom_widgets/upload_status_indicator.dart';
import 'package:pawfinder/models/scouting_session.dart';
import 'package:pawfinder/providers/scouting_providers.dart';

class ScoutPage extends ConsumerStatefulWidget {
  const ScoutPage({super.key});

  @override
  ConsumerState<ScoutPage> createState() => _ScoutPageState();
}

class _ScoutPageState extends ConsumerState<ScoutPage> {
  String _searchQuery = '';
  Scout? _selectedScout;
  bool _showTimeout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(scoutingSessionProvider);
      if (mounted) {
        setState(() {
          _selectedScout = session.scout;
        });
      }

      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() => _showTimeout = true);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scoutsAsync = ref.watch(scoutsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/config'),
        ),
        title: const Text('Select Scout'),
        actions: const [UploadStatusIndicator()],
        actionsPadding: EdgeInsets.only(right: 8),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                SearchBar(
                  hintText: 'Search scouts...',
                  elevation: WidgetStateProperty.all(0.0),
                  shape: WidgetStateProperty.all(
                    StadiumBorder(
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                        width: 1,
                      ),
                    ),
                  ),
                  padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                    const EdgeInsets.symmetric(horizontal: 16.0),
                  ),
                  leading: const Icon(Icons.search),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ).animate().fadeIn(duration: 500.ms),
                const SizedBox(height: 8),
                Expanded(
                  child: scoutsAsync.when(
                    data: (scouts) {
                      final filtered = scouts.where((s) {
                        return s.name.toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        );
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            scouts.isEmpty
                                ? 'No scouts found'
                                : 'No scouts match "$_searchQuery"',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        );
                      }

                      return ClipRect(
                        child: ListView.separated(
                          clipBehavior: Clip.hardEdge,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final scout = filtered[index];
                            final isSelected =
                                _selectedScout?.uuid == scout.uuid;

                            return Material(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Colors.transparent,
                              shape: const StadiumBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: isSelected
                                      ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withAlpha(100)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                  child: Text(
                                    scout.name.isNotEmpty
                                        ? scout.name[0].toUpperCase()
                                        : '?',
                                  ),
                                ),
                                title: Text(scout.name),
                                selected: isSelected,
                                shape: const StadiumBorder(),
                                onTap: () {
                                  setState(() => _selectedScout = scout);
                                  ref
                                      .read(scoutingSessionProvider.notifier)
                                      .setScout(scout);
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                    loading: () => _showTimeout
                        ? _buildTimeoutWidget(context)
                        : const Center(child: CircularProgressIndicator()),
                    error: (_, _) => _buildTimeoutWidget(context),
                  ),
                ),
                SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _selectedScout != null
                            ? () {
                                ref
                                    .read(scoutingSessionProvider.notifier)
                                    .setScout(_selectedScout!);
                                context.go('/match-select');
                              }
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 300.ms, duration: 500.ms)
                    .slideY(
                      begin: 0.3,
                      end: 0,
                      delay: 300.ms,
                      duration: 500.ms,
                      curve: Curves.easeOut,
                    )
                    .shimmer(
                      delay: 900.ms,
                      duration: 1500.ms,
                      color: Colors.white24,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeoutWidget(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load scouts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Unable to connect to the server',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () {
              setState(() => _showTimeout = false);
              ref.invalidate(scoutsProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              const guestScout = Scout(name: 'Guest', uuid: 'guest');
              setState(() => _selectedScout = guestScout);
              ref.read(scoutingSessionProvider.notifier).setScout(guestScout);
            },
            icon: const Icon(Icons.person_outline),
            label: const Text('Continue as Guest'),
          ),
        ],
      ),
    );
  }
}
