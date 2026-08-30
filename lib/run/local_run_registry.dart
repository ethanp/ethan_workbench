import 'dart:async';

import 'local_run_controls.dart';
import 'local_run_key.dart';
import 'local_run_persistence.dart';
import 'local_run_slot.dart';
import 'local_run_state.dart';

/// Shared Mac/phone surface for concurrent local `flutter run`s.
abstract class LocalRunRegistry() {
  LocalRunControls controlsFor(LocalRunKey runKey);
  LocalRunState stateFor(LocalRunKey runKey);
  Stream<void> get changes;
  List<LocalRunState> get knownStates;
  int get activeCount;
  Stream<LocalRunState> get stateUpdates;
}

/// Mac companion: one [LocalRunSlot] per [LocalRunKey].
class MacLocalRunRegistry({LocalRunPersistence? persistence})
    implements LocalRunRegistry {
  final LocalRunPersistence _persistence = persistence ?? LocalRunPersistence();
  final Map<LocalRunKey, LocalRunSlot> _slots = {};
  final Map<LocalRunKey, StreamSubscription<LocalRunState>> _subscriptions = {};
  final _changes = StreamController<void>.broadcast();
  final _stateUpdates = StreamController<LocalRunState>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<LocalRunState> get stateUpdates => _stateUpdates.stream;

  @override
  List<LocalRunState> get knownStates => [
    for (final slot in _slots.values) slot.state,
  ];

  @override
  int get activeCount => _slots.values.where((slot) => slot.isActive).length;

  @override
  LocalRunState stateFor(LocalRunKey runKey) =>
      _slots[runKey]?.state ?? LocalRunState.idle;

  @override
  LocalRunControls controlsFor(LocalRunKey runKey) => _slotFor(runKey);

  LocalRunSlot _slotFor(LocalRunKey runKey) {
    final existing = _slots[runKey];
    if (existing != null) return existing;
    final slot = LocalRunSlot(runKey: runKey, persistence: _persistence);
    _slots[runKey] = slot;
    _subscriptions[runKey] = slot.updates.listen((state) {
      if (!_changes.isClosed) {
        _changes.add(null);
      }
      if (!_stateUpdates.isClosed) {
        _stateUpdates.add(state);
      }
    });
    return slot;
  }

  Future<void> restorePersisted() async {
    final records = await _persistence.readAll();
    await Future.wait([
      for (final record in records) _slotFor(record.runKey).restorePersisted(),
    ]);
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await Future.wait([for (final slot in _slots.values) slot.dispose()]);
    _slots.clear();
    await _changes.close();
    await _stateUpdates.close();
  }
}
