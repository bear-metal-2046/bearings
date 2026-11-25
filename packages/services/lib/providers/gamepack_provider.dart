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

final gamePackProvider = Provider.autoDispose
    .family<AsyncValue<GamePack>, String>((ref, id) {
      final grove = ref.watch(bearingsGroveProvider);
      return ref
          .watch(groveQueryProvider(grove.query<GamePack>().byId(id)))
          .whenData((snapshot) {
            final gamePack = snapshot.requireAvailable().items.singleOrNull;
            if (gamePack == null) {
              throw const GroveException('not_found', 'GamePack unavailable');
            }
            return gamePack;
          });
    });

final eventGamePackProvider = Provider.autoDispose
    .family<AsyncValue<GamePack?>, String>((ref, event) {
      return ref
          .watch(eventGamePackBindingProvider(event))
          .flatMap(
            (binding) => binding?.gamePack == null
                ? const AsyncData(null)
                : ref.watch(gamePackProvider(binding!.gamePack!.id)),
          );
    });

/// Existing installations use the schedule's pack until practice is configured.
final practiceGamePackProvider = Provider.autoDispose
    .family<AsyncValue<GamePack?>, String>((ref, scheduleEvent) {
      return ref
          .watch(eventGamePackBindingProvider(practiceGamePackKey))
          .flatMap(
            (binding) => binding == null
                ? ref.watch(eventGamePackProvider(scheduleEvent))
                : binding.gamePack == null
                ? const AsyncData(null)
                : ref.watch(gamePackProvider(binding.gamePack!.id)),
          );
    });

final eventGamePackHasDataProvider = Provider.autoDispose
    .family<AsyncValue<bool>, String>((ref, event) {
      final grove = ref.watch(bearingsGroveProvider);
      return ref
          .watch(
            groveQueryProvider(
              grove.query<GamePackObservation>().where(
                GamePackObservationFields.event.equals(EntityRef(event)),
              ),
            ),
          )
          .whenData((snapshot) => snapshot.requireAvailable().items.isNotEmpty);
    });

final gamePackFormsLockedProvider = Provider.autoDispose
    .family<AsyncValue<bool>, String>((ref, gamePack) {
      final grove = ref.watch(bearingsGroveProvider);
      final bindings = ref.watch(
        groveQueryProvider(
          grove.query<EventGamePack>().where(
            EventGamePackFields.gamePack.equals(EntityRef(gamePack)),
          ),
        ),
      );
      final observations = ref.watch(
        groveQueryProvider(grove.query<GamePackObservation>()),
      );
      return bindings.flatMap((snapshot) {
        final events = snapshot
            .requireAvailable()
            .items
            .map((binding) => binding.id)
            .toSet();
        if (events.isEmpty) return const AsyncData(false);
        return observations.whenData(
          (rows) => rows.requireAvailable().items.any(
            (row) => events.contains(row.event.id),
          ),
        );
      });
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
