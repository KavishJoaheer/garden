import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant_filter.dart';
import 'package:gardnx_app/features/plant_database/domain/models/companion_rule.dart';

class PlantRepository {
  final FirebaseFirestore _firestore;

  // In-memory caches
  List<Plant>? _cachedPlants;
  List<CompanionRule>? _cachedRules;
  final Map<String, Plant> _plantById = {};

  PlantRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ---- Plants ---------------------------------------------------------------

  /// Returns curated plants (`userId == null`) plus any plants owned by [uid].
  /// When [uid] is null the user is signed out and only curated plants are
  /// returned. Firestore rejects `whereIn: [null, …]`, so we fan out into two
  /// queries and merge by doc id.
  Future<List<Plant>> getAllPlants({
    bool forceRefresh = false,
    String? uid,
  }) async {
    if (_cachedPlants != null && !forceRefresh) return _cachedPlants!;

    List<Plant> plants = [];
    try {
      final col = _firestore.collection('plants');
      final curatedFuture = col.where('userId', isNull: true).get();
      final ownedFuture = (uid != null && uid.isNotEmpty)
          ? col.where('userId', isEqualTo: uid).get()
          : null;
      final curatedSnap = await curatedFuture;
      final ownedSnap = ownedFuture != null ? await ownedFuture : null;
      final byId = <String, Plant>{};
      for (final doc in curatedSnap.docs) {
        byId[doc.id] = Plant.fromFirestore(doc);
      }
      if (ownedSnap != null) {
        for (final doc in ownedSnap.docs) {
          byId[doc.id] = Plant.fromFirestore(doc);
        }
      }
      plants = byId.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      // ignore — fall through to local fallback
    }

    // Fall back to bundled asset data when Firestore is empty or unreachable
    if (plants.isEmpty) {
      plants = await _loadLocalPlants();
    }

    if (plants.isNotEmpty) {
      _cachedPlants = plants;
      _plantById.clear();
      for (final p in plants) {
        _plantById[p.id] = p;
      }
    }
    return _cachedPlants ?? plants;
  }

  Future<List<Plant>> _loadLocalPlants() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/data/plants.json');
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => Plant.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Plant?> getPlantById(String id) async {
    if (_plantById.containsKey(id)) return _plantById[id];
    try {
      final doc = await _firestore.collection('plants').doc(id).get();
      if (!doc.exists) return null;
      final plant = Plant.fromFirestore(doc);
      _plantById[id] = plant;
      return plant;
    } catch (_) {
      return null;
    }
  }

  Future<List<Plant>> searchPlants(String query) async {
    final all = await getAllPlants();
    final filter = PlantFilter(searchQuery: query);
    return filter.apply(all);
  }

  Future<List<Plant>> filterPlants(PlantFilter filter) async {
    final all = await getAllPlants();
    return filter.apply(all);
  }

  // ---- Companion Rules -------------------------------------------------------

  Future<List<CompanionRule>> getCompanionRules({
    bool forceRefresh = false,
  }) async {
    if (_cachedRules != null && !forceRefresh) return _cachedRules!;

    try {
      final snapshot =
          await _firestore.collection('companion_rules').get();
      final rules = snapshot.docs
          .map((doc) =>
              CompanionRule.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
      _cachedRules = rules;
      return rules;
    } catch (_) {
      return _cachedRules ?? [];
    }
  }

  Future<List<CompanionRule>> getCompanionsForPlant(String plantId) async {
    final rules = await getCompanionRules();
    return rules
        .where((r) =>
            (r.plantAId == plantId || r.plantBId == plantId) &&
            r.type == CompanionType.companion)
        .toList();
  }

  Future<List<CompanionRule>> getIncompatiblesForPlant(String plantId) async {
    final rules = await getCompanionRules();
    return rules
        .where((r) =>
            (r.plantAId == plantId || r.plantBId == plantId) &&
            r.type == CompanionType.incompatible)
        .toList();
  }

  Future<List<Plant>> getCompanionPlants(String plantId) async {
    final rules = await getCompanionsForPlant(plantId);
    final ids = rules.map((r) => r.partnerOf(plantId)!).toList();
    final plants = <Plant>[];
    for (final id in ids) {
      final p = await getPlantById(id);
      if (p != null) plants.add(p);
    }
    return plants;
  }

  // ---- Plants suitable for current season / region --------------------------

  Future<List<Plant>> getPlantsForMonth(int month) async {
    final all = await getAllPlants();
    return all.where((p) => p.timing.sowMonths.contains(month)).toList();
  }

  Future<List<Plant>> getPlantsByCategory(String category) async {
    final all = await getAllPlants();
    return all.where((p) => p.category == category).toList();
  }

  /// Saves [plant] to the shared catalog, tagged with [uid] so that Firestore
  /// rules and per-user reads can scope it to the owner. Curated (global)
  /// plants are seeded with `userId: null` by a separate admin script — app
  /// code should never pass an empty uid here.
  Future<String> addPlant(Plant plant, {required String uid}) async {
    if (uid.isEmpty) {
      throw StateError('addPlant requires a non-empty uid');
    }
    final data = plant.toJson();
    data['userId'] = uid;
    final docRef = await _firestore.collection('plants').add(data);
    invalidateCache();
    return docRef.id;
  }

  void invalidateCache() {
    _cachedPlants = null;
    _cachedRules = null;
    _plantById.clear();
  }
}
