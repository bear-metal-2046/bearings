import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:riverpod/riverpod.dart';

import 'grove_provider.dart';

final eventGamePackBindingProvider = Provider.autoDispose
    .family<AsyncValue<EventGamePack?>, String>((ref, event) {
      final grove = ref.watch(bearingsGroveProvider);
      return ref
          .watch(groveQueryProvider(grove.query<EventGamePack>().byId(event)))
          .whenData(
            (snapshot) => snapshot.requireAvailable().items.singleOrNull,
          );
    });

final gamePackReleaseProvider = Provider.autoDispose
    .family<AsyncValue<GamePackRelease>, String>((ref, id) {
      final grove = ref.watch(bearingsGroveProvider);
      return ref
          .watch(groveQueryProvider(grove.query<GamePackRelease>().byId(id)))
          .whenData((snapshot) {
            final release = snapshot.requireAvailable().items.singleOrNull;
            if (release == null) {
              throw const GroveException(
                'not_found',
                'Published GamePack unavailable',
              );
            }
            return release;
          });
    });

final eventGamePackProvider = Provider.autoDispose
    .family<AsyncValue<GamePackRelease?>, String>((ref, event) {
      return ref
          .watch(eventGamePackBindingProvider(event))
          .flatMap(
            (binding) => binding == null
                ? const AsyncData(null)
                : ref.watch(gamePackReleaseProvider(binding.release.id)),
          );
    });

final eventAnalysisGamePackProvider = Provider.autoDispose
    .family<AsyncValue<GamePackRelease?>, String>((ref, event) {
      return ref
          .watch(eventGamePackBindingProvider(event))
          .flatMap(
            (binding) => binding == null
                ? const AsyncData(null)
                : ref.watch(
                    gamePackReleaseProvider(
                      binding.effectiveAnalysisRelease.id,
                    ),
                  ),
          );
    });

final eventTbaRevisionsProvider = Provider.autoDispose
    .family<AsyncValue<QueryResult<TbaMatchRevision>>, String>((ref, event) {
      final grove = ref.watch(bearingsGroveProvider);
      return ref.watch(
        groveQueryProvider(
          grove.query<TbaMatchRevision>().where(
            TbaMatchRevisionFields.event.equals(EntityRef(event)),
          ),
        ),
      );
    });
