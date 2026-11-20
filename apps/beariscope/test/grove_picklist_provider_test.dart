import 'dart:async';

import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CurrentEvent extends CurrentEvent {
  @override
  String build() => 'pnw';
}

class _Authenticated extends AuthStatusNotifier {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

class _Transport extends MemoryGroveTransport {
  _Transport(super.registry);

  bool rejectWrites = false;
  final connectionChanges = StreamController<bool>.broadcast();

  @override
  Stream<QuerySnapshot> watch(QueryDescription query) => Stream.multi((watch) {
    final snapshots = super
        .watch(query)
        .listen(watch.add, onError: watch.addError);
    final connection = connectionChanges.stream.listen((connected) async {
      if (connected) {
        watch.add(await fetch(query));
      } else {
        watch.addError(const GroveOffline());
      }
    });
    watch.onCancel = () async {
      await connection.cancel();
      await snapshots.cancel();
    };
  });

  @override
  Future<EntityRecord> mutate(EntityMutation mutation) {
    if (rejectWrites) return Future.error(const GroveOffline());
    return super.mutate(mutation);
  }

  @override
  Future<void> close() async {
    await connectionChanges.close();
    await super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'picklist library saves local drafts and observes committed shared edits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final registry = bearingsEntityRegistry();
      final transport = _Transport(registry);
      final grove = Grove(registry: registry, transport: transport);
      addTearDown(grove.close);
      final container = ProviderContainer(
        overrides: [
          currentEventProvider.overrideWith(_CurrentEvent.new),
          sharedPreferencesProvider.overrideWithValue(prefs),
          bearingsGroveProvider.overrideWithValue(grove),
          authStatusProvider.overrideWith(_Authenticated.new),
          permissionCheckerProvider.overrideWithValue(
            const PermissionChecker(
              permissions: {
                'strategy.picklist.read',
                'strategy.picklist.mutate',
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final updates = StreamController<List<Picklist>>.broadcast();
      addTearDown(updates.close);
      final subscription = container.listen(
        picklistLibraryProvider,
        (_, next) => updates.add(next),
      );
      addTearDown(subscription.close);
      final library = container.read(picklistLibraryProvider.notifier);

      final local = await library.create(title: 'Device notes');
      final remote = await library.create(
        title: 'Shared rankings',
        teamKeys: ['frc2046'],
        mode: PicklistMode.multiplayer,
      );
      final updated = updates.stream.firstWhere(
        (items) => items.any(
          (item) => item.id == remote.id && item.title == 'Final rankings',
        ),
      );
      await grove.update<GrovePicklist>(
        remote.id,
        (record) =>
            record.customize(title: 'Final rankings', at: DateTime.now()),
      );
      final items = await updated.timeout(const Duration(seconds: 3));
      expect(items.map((item) => item.id), containsAll([local.id, remote.id]));
      final stored = prefs.getString(PicklistLibraryNotifier.storageKey)!;
      expect(stored, contains(local.id));
      expect(stored, isNot(contains(remote.id)));

      transport.rejectWrites = true;
      await expectLater(
        library.create(title: 'Unavailable', mode: PicklistMode.multiplayer),
        throwsA(isA<GroveOffline>()),
      );
      await expectLater(
        library.delete(remote.id),
        throwsA(isA<GroveOffline>()),
      );
      expect(
        container.read(picklistLibraryProvider).map((item) => item.id),
        contains(remote.id),
      );
      expect(
        container.read(picklistLibraryProvider).map((item) => item.title),
        isNot(contains('Unavailable')),
      );

      // After Grove reports a disconnect, the app blocks shared edits even if
      // the transport would accept the next write. Local lists stay editable.
      transport.rejectWrites = false;
      final disconnected = updates.stream.firstWhere(
        (_) => container.read(sharedPicklistsOfflineProvider),
      );
      transport.connectionChanges.add(false);
      final cached = await disconnected.timeout(const Duration(seconds: 3));
      final shared = cached.singleWhere((item) => item.id == remote.id);
      expect(shared.teamKeys, ['frc2046']);
      expect(library.canEdit(shared), isFalse);
      await expectLater(
        library.setTeams(shared.id, [], basedOn: shared),
        throwsA(isA<GroveOffline>()),
      );
      expect(library.canEdit(local), isTrue);
      await library.customize(local.id, title: 'Offline notes');
      expect(
        container.read(picklistLibraryProvider).map((item) => item.title),
        contains('Offline notes'),
      );

      final reconnected = updates.stream.firstWhere(
        (_) => !container.read(sharedPicklistsOfflineProvider),
      );
      transport.connectionChanges.add(true);
      await reconnected.timeout(const Duration(seconds: 3));
      expect(library.canEdit(shared), isTrue);
      await library.setTeams(shared.id, ['frc2046', 'frc254'], basedOn: shared);
    },
  );
}
