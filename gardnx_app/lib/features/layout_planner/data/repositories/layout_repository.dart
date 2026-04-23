import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:gardnx_app/config/constants/api_constants.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/garden_layout.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/layout_suggestion.dart';

class EngineStatus {
  final bool available;
  final String reason;
  const EngineStatus({required this.available, required this.reason});
  factory EngineStatus.fromJson(Map<String, dynamic> json) => EngineStatus(
    available: json['available'] as bool? ?? false,
    reason: json['reason'] as String? ?? '',
  );
}

class RecommendationResult {
  final List<LayoutSuggestion> suggestions;
  final String engineUsed;
  final String? engineRequested;
  final String? fallbackReason;
  RecommendationResult({
    required this.suggestions,
    required this.engineUsed,
    this.engineRequested,
    this.fallbackReason,
  });
}

class LayoutRepository {
  final FirebaseFirestore _firestore;
  final Dio _dio;

  LayoutRepository({FirebaseFirestore? firestore, Dio? dio})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.baseUrl,
              connectTimeout: ApiConstants.connectTimeout,
              receiveTimeout: ApiConstants.receiveTimeout,
            ));

  // ---- Generate layout (backend call) ----------------------------------------

  Future<GardenLayout> generateLayout({
    required String gardenId,
    required String bedId,
    required double widthCm,
    required double heightCm,
    required List<String> selectedPlantIds,
    required String sunExposure,
    required String season,
  }) async {
    try {
      final response = await _dio.post('/layout/generate', data: {
        'bed': {
          'width_cm': widthCm,
          'height_cm': heightCm,
          'sun_exposure': sunExposure,
        },
        'plants': selectedPlantIds
            .map((id) => {
                  'plant_id': id,
                  'quantity':
                      ((widthCm * heightCm) / (selectedPlantIds.length * 900))
                          .ceil()
                          .clamp(1, 10),
                })
            .toList(),
      });

      if (response.statusCode == 200 && response.data != null) {
        return GardenLayout.fromJson(response.data as Map<String, dynamic>);
      }
    } on DioException {
      // Fall through to default
    }

    // Return default empty layout on failure
    final cellSize = 30.0;
    return GardenLayout(
      gardenId: gardenId,
      bedId: bedId,
      gridRows: (heightCm / cellSize).floor().clamp(1, 20),
      gridCols: (widthCm / cellSize).floor().clamp(1, 20),
      cellSizeCm: cellSize,
      placements: [],
    );
  }

  // ---- Get recommendations (backend call) ------------------------------------

  Future<RecommendationResult> getRecommendations({
    required String gardenId,
    required String bedId,
    required double widthCm,
    required double heightCm,
    required String sunExposure,
    required String soilType,
    required String season,
    required String region,
    List<String> preferences = const [],
    String? experienceLevel,
    String? preferredEngine,
  }) async {
    try {
      final data = <String, dynamic>{
        'garden_id': gardenId,
        'bed_id': bedId,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'sun_exposure': sunExposure,
        'soil_type': soilType,
        'season': season,
        'region': region,
        'preferences': preferences,
      };
      if (experienceLevel != null) data['experience_level'] = experienceLevel;
      if (preferredEngine != null) data['preferred_engine'] = preferredEngine;

      final response = await _dio.post('/layout/recommend', data: data);

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data as Map<String, dynamic>;
        final list = body['recommendations'] as List<dynamic>? ?? [];
        final suggestions = list
            .map((e) =>
                LayoutSuggestion.fromJson(e as Map<String, dynamic>))
            .toList();
        return RecommendationResult(
          suggestions: suggestions,
          engineUsed: body['engine_used'] as String? ?? 'rules',
          engineRequested: body['engine_requested'] as String?,
          fallbackReason: body['fallback_reason'] as String?,
        );
      }
    } on DioException {
      // Fall through
    }
    return RecommendationResult(suggestions: [], engineUsed: 'rules');
  }

  Future<Map<String, EngineStatus>> getEngineStatus() async {
    try {
      final response = await _dio.get('/plants/engine-status');
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, EngineStatus.fromJson(value as Map<String, dynamic>)),
        );
      }
    } on DioException {
      // Fall through
    }
    return {
      'gemini': EngineStatus(available: false, reason: 'Backend unavailable'),
      'ollama': EngineStatus(available: false, reason: 'Backend unavailable'),
      'rules': EngineStatus(available: true, reason: 'Built-in rules'),
    };
  }

  // ---- Validate layout (backend call) ----------------------------------------

  Future<List<LayoutWarning>> validateLayout({
    required GardenLayout layout,
    required double bedWidthCm,
    required double bedHeightCm,
    String sunExposure = 'full_sun',
    String soilType = 'loamy',
  }) async {
    try {
      final response = await _dio.post('/layout/validate', data: {
        'bed': {
          'width_cm': bedWidthCm,
          'height_cm': bedHeightCm,
          'sun_exposure': sunExposure,
          'soil_type': soilType,
        },
        'placements': layout.placements
            .map((p) => {
                  'plant_id': p.plantId,
                  'plant_name': p.plantName,
                  'row': p.startRow,
                  'col': p.startCol,
                  'span_rows': p.rowSpan,
                  'span_cols': p.colSpan,
                  'count': p.count,
                })
            .toList(),
      });
      if (response.statusCode == 200 && response.data != null) {
        final warnings =
            response.data['warnings'] as List<dynamic>? ?? [];
        return warnings
            .map((e) => LayoutWarning.fromJson({
                  'type': e['type'],
                  'message': e['message'],
                  // Backend emits plant1_id; expose as plant_id for UI filtering.
                  'plant_id': e['plant1_id'] ?? e['plant2_id'],
                }))
            .toList();
      }
    } on DioException {
      // Fall through
    }
    return [];
  }

  // ---- Firestore persistence -------------------------------------------------

  Future<String> saveLayout(GardenLayout layout) async {
    final data = layout.toJson();
    data['saved_at'] = FieldValue.serverTimestamp();

    if (layout.id != null) {
      await _firestore
          .collection('gardens')
          .doc(layout.gardenId)
          .collection('layouts')
          .doc(layout.id)
          .set(data, SetOptions(merge: true));
      return layout.id!;
    } else {
      final docRef = await _firestore
          .collection('gardens')
          .doc(layout.gardenId)
          .collection('layouts')
          .add(data);
      return docRef.id;
    }
  }

  Future<List<GardenLayout>> getLayouts(String gardenId) async {
    try {
      final snapshot = await _firestore
          .collection('gardens')
          .doc(gardenId)
          .collection('layouts')
          .orderBy('saved_at', descending: true)
          .get();
      return snapshot.docs
          .map((doc) =>
              GardenLayout.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<GardenLayout?> getLatestLayout(
      String gardenId, String bedId) async {
    try {
      final snapshot = await _firestore
          .collection('gardens')
          .doc(gardenId)
          .collection('layouts')
          .where('bed_id', isEqualTo: bedId)
          .orderBy('saved_at', descending: true)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return GardenLayout.fromJson({...doc.data(), 'id': doc.id});
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteLayout(String gardenId, String layoutId) async {
    await _firestore
        .collection('gardens')
        .doc(gardenId)
        .collection('layouts')
        .doc(layoutId)
        .delete();
  }
}
