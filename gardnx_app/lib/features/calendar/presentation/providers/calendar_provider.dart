import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/calendar/domain/models/planting_event.dart';
import 'package:gardnx_app/features/calendar/data/repositories/calendar_repository.dart';
import 'package:gardnx_app/shared/providers/firebase_providers.dart';

final calendarRepositoryProvider =
    Provider<CalendarRepository>((ref) => CalendarRepository());

// Current garden id context — set when user saves a layout or taps a garden.
// Resets to null on sign-out (invalidated in app.dart listener).
final activeGardenIdProvider = StateProvider<String?>((ref) => null);

/// Auto-resolves which garden to show on the calendar.
///
/// Priority: explicit [activeGardenIdProvider] → most recent garden from
/// Firestore for the *currently signed-in user only*.
/// Rebuilds whenever [currentFirebaseUserProvider] changes so it is always
/// scoped to the right account.
final resolvedGardenIdProvider = FutureProvider<String?>((ref) async {
  // Watch the auth state so this re-executes on sign-in / sign-out.
  final user = ref.watch(currentFirebaseUserProvider);
  if (user == null) return null;

  final explicit = ref.watch(activeGardenIdProvider);
  if (explicit != null && explicit.isNotEmpty) return explicit;

  try {
    final firestore = ref.read(firestoreProvider);
    // No orderBy — avoids composite-index requirement; sort client-side.
    final snap = await firestore
        .collection('gardens')
        .where('userId', isEqualTo: user.uid) // always scoped to current user
        .limit(20)
        .get();
    if (snap.docs.isEmpty) return null;

    // Pick the most-recently updated garden. Read both camelCase (canonical)
    // and snake_case (legacy) timestamp fields.
    final sorted = snap.docs.toList()
      ..sort((a, b) {
        final da = a.data();
        final db = b.data();
        final aTs = da['updatedAt'] ??
            da['updated_at'] ??
            da['createdAt'] ??
            da['created_at'];
        final bTs = db['updatedAt'] ??
            db['updated_at'] ??
            db['createdAt'] ??
            db['created_at'];
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return (bTs as Comparable).compareTo(aTs as Comparable);
      });

    final id = sorted.first.id;
    // Cache so future reads don't hit Firestore again in the same session.
    ref.read(activeGardenIdProvider.notifier).state = id;
    return id;
  } catch (_) {
    return null;
  }
});

/// Single source of truth for the events list shown on the calendar.
///
/// Keyed on the resolved gardenId so switching gardens always loads fresh
/// data from Firestore. Tap-to-complete mutates this notifier; the screen
/// reads its state so the toggle is reflected immediately without refetching.
class GardenEventsNotifier
    extends StateNotifier<AsyncValue<List<PlantingEvent>>> {
  final CalendarRepository _repo;
  final String? gardenId;

  GardenEventsNotifier(this._repo, this.gardenId)
      : super(const AsyncLoading()) {
    _load();
  }

  Future<void> _load() async {
    final gid = gardenId;
    if (gid == null || gid.isEmpty) {
      state = const AsyncData(<PlantingEvent>[]);
      return;
    }
    try {
      final events = await _repo.getEvents(gid);
      state = AsyncData(events);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> reload() => _load();

  /// Optimistic toggle: flip UI first, persist second, roll back on failure.
  /// Returns a non-null error message only when persistence fails.
  Future<String?> toggleEventCompletion(PlantingEvent event) async {
    final gid = gardenId;
    if (gid == null || gid.isEmpty) return 'Garden not set';
    final current = state.value;
    if (current == null) return 'Events not loaded';

    final updated = event.copyWith(isCompleted: !event.isCompleted);
    // Apply optimistic update immediately so UI feels instant.
    state = AsyncData(
      current.map((e) => e.id == event.id ? updated : e).toList(),
    );
    try {
      await _repo.updateEventCompletion(gid, event.id, updated.isCompleted);
      return null; // success
    } catch (e) {
      // Roll back to prior list on persistence failure.
      state = AsyncData(current);
      return e.toString();
    }
  }
}

final gardenEventsProvider = StateNotifierProvider<
    GardenEventsNotifier, AsyncValue<List<PlantingEvent>>>((ref) {
  final gardenId = ref.watch(resolvedGardenIdProvider).valueOrNull;
  final repo = ref.read(calendarRepositoryProvider);
  return GardenEventsNotifier(repo, gardenId);
});

// Events grouped by day (for table_calendar markerBuilder)
final eventsByDayProvider =
    Provider<Map<DateTime, List<PlantingEvent>>>((ref) {
  final eventsAsync = ref.watch(gardenEventsProvider);
  return eventsAsync.when(
    data: (events) {
      final map = <DateTime, List<PlantingEvent>>{};
      for (final event in events) {
        final day = DateTime(
            event.date.year, event.date.month, event.date.day);
        map.putIfAbsent(day, () => []).add(event);
      }
      return map;
    },
    loading: () => {},
    error: (_, __) => {},
  );
});

// Selected calendar day
final selectedCalendarDayProvider =
    StateProvider<DateTime>((ref) => DateTime.now());
