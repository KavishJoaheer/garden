import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/calendar/domain/models/task.dart';
import 'package:gardnx_app/features/calendar/data/repositories/calendar_repository.dart';
import 'package:gardnx_app/features/calendar/presentation/providers/calendar_provider.dart';
import 'package:gardnx_app/shared/providers/firebase_providers.dart';

// All tasks for a specific garden
final gardenTasksProvider =
    FutureProvider.family<List<PlantingTask>, String>((ref, gardenId) async {
  final repo = ref.read(calendarRepositoryProvider);
  return repo.getTasks(gardenId);
});

// Upcoming tasks across every garden owned by the signed-in user (next 14 days).
// Rebuilds automatically when the auth state changes.
final upcomingTasksProvider = FutureProvider<List<PlantingTask>>((ref) async {
  final user = ref.watch(currentFirebaseUserProvider);
  if (user == null) return const [];
  final repo = ref.read(calendarRepositoryProvider);
  return repo.getUpcomingTasks(uid: user.uid, daysAhead: 14);
});

// StateNotifier for managing tasks with complete/uncomplete actions
class TasksNotifier extends StateNotifier<AsyncValue<List<PlantingTask>>> {
  final CalendarRepository _repo;
  final String gardenId;

  TasksNotifier(this._repo, this.gardenId)
      : super(const AsyncLoading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final tasks = await _repo.getTasks(gardenId);
      state = AsyncData(tasks);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> reload() => _load();

  Future<void> toggleCompletion(PlantingTask task) async {
    final current = state.value;
    if (current == null) return;
    final completed = !task.isCompleted;
    final updated = task.copyWith(
      isCompleted: completed,
      completedAt: completed ? DateTime.now() : null,
    );
    state = AsyncData(
      current.map((t) => t.id == task.id ? updated : t).toList(),
    );
    await _repo.completeTask(gardenId, task.id, completed);
  }

  List<PlantingTask> get upcoming {
    final tasks = state.value ?? [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return tasks
        .where((t) =>
            !t.isCompleted &&
            !t.dueDate.isBefore(today))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  List<PlantingTask> get completed {
    final tasks = state.value ?? [];
    return tasks
        .where((t) => t.isCompleted)
        .toList()
      ..sort((a, b) =>
          (b.completedAt ?? b.dueDate)
              .compareTo(a.completedAt ?? a.dueDate));
  }

  List<PlantingTask> get overdue {
    final tasks = state.value ?? [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return tasks
        .where((t) =>
            !t.isCompleted && t.dueDate.isBefore(today))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }
}

final tasksNotifierProvider = StateNotifierProvider.family<TasksNotifier,
    AsyncValue<List<PlantingTask>>, String>(
  (ref, gardenId) => TasksNotifier(
    ref.read(calendarRepositoryProvider),
    gardenId,
  ),
);

// Convenience: tasks for the active garden
final activeGardenTasksProvider =
    Provider<AsyncValue<List<PlantingTask>>>((ref) {
  final gardenId = ref.watch(activeGardenIdProvider);
  if (gardenId == null) return const AsyncData([]);
  return ref.watch(tasksNotifierProvider(gardenId));
});
