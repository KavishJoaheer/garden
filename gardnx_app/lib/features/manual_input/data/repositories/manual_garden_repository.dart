import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gardnx_app/config/constants/firebase_constants.dart';
import 'package:gardnx_app/features/manual_input/domain/models/manual_bed.dart';

class ManualGardenRepository {
  final FirebaseFirestore _firestore;

  ManualGardenRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _bedsCollection(String gardenId) =>
      _firestore.collection('gardens').doc(gardenId).collection('beds');

  DocumentReference<Map<String, dynamic>> _gardenDoc(String gardenId) =>
      _firestore.collection('gardens').doc(gardenId);

  Future<List<ManualBed>> getBeds(String gardenId) async {
    try {
      final snapshot = await _bedsCollection(gardenId).get();
      return snapshot.docs
          .map((doc) => ManualBed.fromFirestore(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ManualBed> addBed(String gardenId, ManualBed bed) async {
    final docRef = await _bedsCollection(gardenId).add(bed.toFirestore());
    await _refreshBedCount(gardenId);
    return bed.copyWith(id: docRef.id);
  }

  Future<void> updateBed(String gardenId, ManualBed bed) async {
    await _bedsCollection(gardenId).doc(bed.id).update(bed.toFirestore());
    await _touchGarden(gardenId);
  }

  Future<void> removeBed(String gardenId, String bedId) async {
    await _bedsCollection(gardenId).doc(bedId).delete();
    await _refreshBedCount(gardenId);
  }

  Future<void> clearBeds(String gardenId) async {
    final snapshot = await _bedsCollection(gardenId).get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    await _refreshBedCount(gardenId);
  }

  Future<String> createGarden(
    String name,
    String region,
    String userId,
  ) async {
    final now = FieldValue.serverTimestamp();
    final docRef = await _firestore.collection('gardens').add({
      'name': name,
      'region': region,
      FirebaseConstants.fieldUserId: userId,
      FirebaseConstants.fieldCreatedAt: now,
      FirebaseConstants.fieldUpdatedAt: now,
      FirebaseConstants.fieldBedCount: 0,
    });
    return docRef.id;
  }

  Future<void> updateGardenTimestamp(String gardenId) => _touchGarden(gardenId);

  Future<void> _touchGarden(String gardenId) async {
    await _gardenDoc(gardenId).update({
      FirebaseConstants.fieldUpdatedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Recomputes and writes `bedCount` on the garden doc after a bed add/delete.
  /// Uses a single aggregate read to avoid loading the whole subcollection.
  Future<void> _refreshBedCount(String gardenId) async {
    try {
      final agg = await _bedsCollection(gardenId).count().get();
      await _gardenDoc(gardenId).update({
        FirebaseConstants.fieldBedCount: agg.count ?? 0,
        FirebaseConstants.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-fatal — the home screen will simply display a stale count.
    }
  }

  Stream<List<ManualBed>> bedsStream(String gardenId) {
    return _bedsCollection(gardenId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ManualBed.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }
}
