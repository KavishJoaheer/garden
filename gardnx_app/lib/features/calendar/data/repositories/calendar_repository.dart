import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:gardnx_app/config/constants/api_constants.dart';
import 'package:gardnx_app/config/constants/firebase_constants.dart';
import 'package:gardnx_app/core/network/api_interceptors.dart';
import 'package:gardnx_app/features/calendar/domain/models/planting_event.dart';
import 'package:gardnx_app/features/calendar/domain/models/task.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';

class CalendarRepository {
  final FirebaseFirestore _firestore;
  final Dio _dio;

  CalendarRepository({FirebaseFirestore? firestore, Dio? dio})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _dio = dio ?? _buildDio();

  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
    ));
    dio.interceptors.add(AuthInterceptor());
    return dio;
  }

  /// Stable, deterministic id so re-generating the same plan overwrites
  /// instead of duplicating. Format: `${bedId}_${plantId}_${type}_${yyyy-mm-dd}`.
  static String stableEventId({
    required String? bedId,
    required String? plantId,
    required String type,
    required DateTime date,
  }) {
    final d = date.toIso8601String().split('T').first;
    return '${bedId ?? "nobed"}_${plantId ?? "noplant"}_${type}_$d';
  }

  static String stableTaskId({
    required String? bedId,
    required String? plantId,
    required String type,
    required DateTime date,
  }) {
    final d = date.toIso8601String().split('T').first;
    return '${bedId ?? "nobed"}_${plantId ?? "noplant"}_${type}_$d';
  }

  // ---- Backend: Generate calendar events from plant list -------------------

  /// Calls /calendar/generate with the correct request shape.
  ///
  /// [plants] are the Plant objects placed in the layout.
  /// Returns [PlantingEvent] objects ready to be saved to Firestore.
  Future<List<PlantingEvent>> generateCalendar({
    required String gardenId,
    required String bedId,
    required String bedName,
    required String region,
    required List<Plant> plants,
  }) async {
    if (plants.isEmpty) return [];

    final plantEntries = plants
        .map((p) => {
              'plant_id': p.id,
              'plant_name': p.name,
              'bed_name': bedName,
              'sowing_months': p.timing.sowMonths,
              'transplant_months': p.timing.transplantMonths,
              'harvest_months': p.timing.harvestMonths,
              'days_to_germination': 7,
              'days_to_harvest': p.timing.daysToMaturity,
            })
        .toList();

    try {
      final response = await _dio.post('/calendar/generate', data: {
        'plants': plantEntries,
        'garden_info': {
          'region': region,
          'latitude': -20.2,
          'longitude': 57.5,
        },
        'start_date': DateTime.now().toIso8601String().split('T')[0],
      });

      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data['events'] as List<dynamic>? ?? [];
        return raw.map((e) {
          final m = e as Map<String, dynamic>;
          final plantId = m['plant_id'] as String?;
          final eventType = PlantingEventTypeExt.fromValue(
              m['event_type'] as String? ?? 'general');
          final date = DateTime.parse(m['start_date'] as String);
          return PlantingEvent(
            id: stableEventId(
                bedId: bedId, plantId: plantId, type: eventType.value, date: date),
            gardenId: gardenId,
            bedId: bedId,
            bedName: bedName,
            plantId: plantId,
            plantName: m['plant_name'] as String? ?? '',
            eventType: eventType,
            date: date,
            notes: m['description'] as String?,
            isCompleted: false,
          );
        }).toList();
      }
    } on DioException {
      // Fall through — caller handles empty list gracefully.
    }
    return [];
  }

  // ---- Firestore: Events ---------------------------------------------------

  CollectionReference<Map<String, dynamic>> _eventsCollection(
          String gardenId) =>
      _firestore
          .collection('gardens')
          .doc(gardenId)
          .collection(FirebaseConstants.eventsSubcollection);

  Future<List<PlantingEvent>> getEvents(String gardenId) async {
    try {
      final snapshot = await _eventsCollection(gardenId)
          .orderBy('date')
          .get();
      return snapshot.docs
          .map((doc) =>
              PlantingEvent.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persists [events] under the given [gardenId]. Every doc is stamped with
  /// [uid] — required by Firestore security rules and the collectionGroup
  /// query in [getUpcomingTasks]. Callers must provide the current user's
  /// uid; this method refuses to write when [uid] is null or empty.
  Future<void> saveEvents(
    String gardenId,
    List<PlantingEvent> events, {
    required String uid,
  }) async {
    if (uid.isEmpty) {
      throw StateError('saveEvents requires a non-empty uid');
    }
    final batch = _firestore.batch();
    for (final event in events) {
      final stamped = event.copyWith(userId: uid, gardenId: gardenId);
      final data = stamped.toJson();
      data[FirebaseConstants.fieldSavedAt] = FieldValue.serverTimestamp();
      if (event.id.isNotEmpty) {
        batch.set(_eventsCollection(gardenId).doc(event.id), data);
      } else {
        batch.set(_eventsCollection(gardenId).doc(), data);
      }
    }
    await batch.commit();
  }

  /// Deletes any existing events under [gardenId] whose `bedId == bedId` and
  /// whose `plantId` is in [plantIds], then writes [events]. Use this when
  /// re-generating a plan for a given bed so stale dates/types don't linger.
  Future<void> replaceEventsForBed({
    required String gardenId,
    required String bedId,
    required List<String> plantIds,
    required List<PlantingEvent> events,
    required String uid,
  }) async {
    if (uid.isEmpty) throw StateError('replaceEventsForBed requires uid');
    await _deleteByBedAndPlants(
      collection: _eventsCollection(gardenId),
      bedId: bedId,
      plantIds: plantIds,
    );
    await saveEvents(gardenId, events, uid: uid);
  }

  Future<void> replaceTasksForBed({
    required String gardenId,
    required String bedId,
    required List<String> plantIds,
    required List<PlantingTask> tasks,
    required String uid,
  }) async {
    if (uid.isEmpty) throw StateError('replaceTasksForBed requires uid');
    await _deleteByBedAndPlants(
      collection: _tasksCollection(gardenId),
      bedId: bedId,
      plantIds: plantIds,
    );
    await saveTasks(gardenId, tasks, uid: uid);
  }

  Future<void> _deleteByBedAndPlants({
    required CollectionReference<Map<String, dynamic>> collection,
    required String bedId,
    required List<String> plantIds,
  }) async {
    if (plantIds.isEmpty) return;
    // Firestore `whereIn` supports up to 10 values; chunk if needed.
    for (int i = 0; i < plantIds.length; i += 10) {
      final chunk = plantIds.sublist(
          i, i + 10 > plantIds.length ? plantIds.length : i + 10);
      try {
        final snap = await collection
            .where(FirebaseConstants.fieldBedId, isEqualTo: bedId)
            .where(FirebaseConstants.fieldPlantId, whereIn: chunk)
            .get();
        if (snap.docs.isEmpty) continue;
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } catch (_) {
        // Non-fatal — save will still proceed (stable ids dedupe the same doc).
      }
    }
  }

  Future<void> updateEventCompletion(
      String gardenId, String eventId, bool completed) async {
    await _eventsCollection(gardenId).doc(eventId).update({
      FirebaseConstants.fieldCompleted: completed,
    });
  }

  // ---- Firestore: Tasks ---------------------------------------------------

  CollectionReference<Map<String, dynamic>> _tasksCollection(
          String gardenId) =>
      _firestore
          .collection('gardens')
          .doc(gardenId)
          .collection(FirebaseConstants.tasksSubcollection);

  Future<List<PlantingTask>> getTasks(String gardenId) async {
    try {
      final snapshot = await _tasksCollection(gardenId)
          .orderBy(FirebaseConstants.fieldDueDate)
          .get();
      return snapshot.docs
          .map((doc) =>
              PlantingTask.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns upcoming tasks across every garden owned by [uid].
  ///
  /// Relies on the composite index `(userId, completed, dueDate)` declared in
  /// firestore.indexes.json and on Firestore rules permitting the caller to
  /// read their own task docs via the collectionGroup rule.
  Future<List<PlantingTask>> getUpcomingTasks({
    required String uid,
    int daysAhead = 14,
  }) async {
    if (uid.isEmpty) return const [];
    final now = DateTime.now();
    final until = now.add(Duration(days: daysAhead));
    try {
      final snapshot = await _firestore
          .collectionGroup(FirebaseConstants.tasksSubcollection)
          .where(FirebaseConstants.fieldUserId, isEqualTo: uid)
          .where(FirebaseConstants.fieldCompleted, isEqualTo: false)
          .where(FirebaseConstants.fieldDueDate,
              isGreaterThanOrEqualTo: now.toIso8601String())
          .where(FirebaseConstants.fieldDueDate,
              isLessThanOrEqualTo: until.toIso8601String())
          .orderBy(FirebaseConstants.fieldDueDate)
          .limit(20)
          .get();
      return snapshot.docs
          .map((doc) =>
              PlantingTask.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persists [tasks] under the given [gardenId] with a mandatory [uid] stamp.
  Future<void> saveTasks(
    String gardenId,
    List<PlantingTask> tasks, {
    required String uid,
  }) async {
    if (uid.isEmpty) {
      throw StateError('saveTasks requires a non-empty uid');
    }
    final batch = _firestore.batch();
    for (final task in tasks) {
      final stamped = task.copyWith(userId: uid, gardenId: gardenId);
      final data = stamped.toJson();
      data[FirebaseConstants.fieldSavedAt] = FieldValue.serverTimestamp();
      if (task.id.isNotEmpty) {
        batch.set(_tasksCollection(gardenId).doc(task.id), data);
      } else {
        batch.set(_tasksCollection(gardenId).doc(), data);
      }
    }
    await batch.commit();
  }

  Future<void> completeTask(
      String gardenId, String taskId, bool completed) async {
    await _tasksCollection(gardenId).doc(taskId).update({
      FirebaseConstants.fieldCompleted: completed,
      FirebaseConstants.fieldCompletedAt:
          completed ? DateTime.now().toIso8601String() : null,
    });
  }

  Stream<List<PlantingTask>> tasksStream(String gardenId) {
    return _tasksCollection(gardenId)
        .orderBy(FirebaseConstants.fieldDueDate)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) =>
                PlantingTask.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }
}
