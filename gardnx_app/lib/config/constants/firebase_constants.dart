/// Firestore collection/subcollection names and Firebase Storage path
/// constants used throughout the GardNx application.
///
/// Canonical schema is **camelCase** across every document. Older documents
/// may still carry snake_case fields; readers should dual-accept, but writers
/// must only emit the camelCase names declared here.
class FirebaseConstants {
  FirebaseConstants._();

  // ---------------------------------------------------------------------------
  // Firestore collections
  // ---------------------------------------------------------------------------
  static const usersCollection = 'users';
  static const gardensCollection = 'gardens';
  static const plantsCollection = 'plants';
  static const climateCacheCollection = 'climate_cache';

  // ---------------------------------------------------------------------------
  // Firestore subcollections
  // ---------------------------------------------------------------------------
  static const bedsSubcollection = 'beds';
  static const layoutsSubcollection = 'layouts';
  static const eventsSubcollection = 'events';
  static const tasksSubcollection = 'tasks';

  // ---------------------------------------------------------------------------
  // Firebase Storage paths
  // ---------------------------------------------------------------------------
  static const photosStoragePath = 'photos';
  static const masksStoragePath = 'masks';
  static const profilePhotosPath = 'profile_photos';

  // ---------------------------------------------------------------------------
  // Firestore field names (canonical camelCase)
  // ---------------------------------------------------------------------------
  static const fieldUserId = 'userId';
  static const fieldGardenId = 'gardenId';
  static const fieldBedId = 'bedId';
  static const fieldBedName = 'bedName';
  static const fieldPlantId = 'plantId';
  static const fieldPlantName = 'plantName';
  static const fieldCreatedAt = 'createdAt';
  static const fieldUpdatedAt = 'updatedAt';
  static const fieldSavedAt = 'savedAt';
  static const fieldCompletedAt = 'completedAt';
  static const fieldDueDate = 'dueDate';
  static const fieldCompleted = 'completed';
  static const fieldBedCount = 'bedCount';
  static const fieldEventType = 'eventType';
  static const fieldTaskType = 'taskType';
}

/// Utility for reading fields that may be written in either camelCase (new
/// canonical) or snake_case (legacy). Used during the Phase B migration
/// window so existing documents keep deserialising.
T? readField<T>(
  Map<String, dynamic> map,
  String camel,
  String snake,
) {
  final v = map[camel] ?? map[snake];
  if (v is T) return v;
  return null;
}
