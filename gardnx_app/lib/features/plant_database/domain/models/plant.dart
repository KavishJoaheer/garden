import 'package:cloud_firestore/cloud_firestore.dart';


class PlantConditions {
  final double minTempC;
  final double maxTempC;
  final String sunRequirement; // 'full_sun', 'partial_shade', 'full_shade'
  final String waterNeeds; // 'low', 'medium', 'high'
  final List<String> suitableSoils;
  final double minHumidity;
  final double maxHumidity;

  const PlantConditions({
    required this.minTempC,
    required this.maxTempC,
    required this.sunRequirement,
    required this.waterNeeds,
    required this.suitableSoils,
    this.minHumidity = 40.0,
    this.maxHumidity = 90.0,
  });

  factory PlantConditions.fromJson(Map<String, dynamic> json) =>
      PlantConditions(
        minTempC: (json['min_temp_c'] as num? ?? 15).toDouble(),
        maxTempC: (json['max_temp_c'] as num? ?? 35).toDouble(),
        sunRequirement: json['sun_requirement'] as String? ?? 'full_sun',
        waterNeeds: json['water_needs'] as String? ?? 'medium',
        suitableSoils: (json['suitable_soils'] as List<dynamic>? ?? ['loam'])
            .cast<String>(),
        minHumidity: (json['min_humidity'] as num? ?? 40).toDouble(),
        maxHumidity: (json['max_humidity'] as num? ?? 90).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'min_temp_c': minTempC,
        'max_temp_c': maxTempC,
        'sun_requirement': sunRequirement,
        'water_needs': waterNeeds,
        'suitable_soils': suitableSoils,
        'min_humidity': minHumidity,
        'max_humidity': maxHumidity,
      };
}

class PlantSpacing {
  final double rowSpacingCm;
  final double plantSpacingCm;
  final int gridCellsRequired;

  const PlantSpacing({
    required this.rowSpacingCm,
    required this.plantSpacingCm,
    this.gridCellsRequired = 1,
  });

  factory PlantSpacing.fromJson(Map<String, dynamic> json) => PlantSpacing(
        rowSpacingCm: (json['row_spacing_cm'] as num? ?? 30).toDouble(),
        plantSpacingCm: (json['plant_spacing_cm'] as num? ?? 30).toDouble(),
        gridCellsRequired: json['grid_cells_required'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'row_spacing_cm': rowSpacingCm,
        'plant_spacing_cm': plantSpacingCm,
        'grid_cells_required': gridCellsRequired,
      };
}

class PlantTiming {
  final List<int> sowMonths;
  final List<int> transplantMonths;
  final List<int> harvestMonths;
  final int daysToMaturity;
  final int daysToTransplant;

  const PlantTiming({
    required this.sowMonths,
    required this.transplantMonths,
    required this.harvestMonths,
    required this.daysToMaturity,
    this.daysToTransplant = 14,
  });

  factory PlantTiming.fromJson(Map<String, dynamic> json) => PlantTiming(
        sowMonths: (json['sow_months'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        transplantMonths:
            (json['transplant_months'] as List<dynamic>? ?? [])
                .map((e) => (e as num).toInt())
                .toList(),
        harvestMonths: (json['harvest_months'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        daysToMaturity: json['days_to_maturity'] as int? ?? 60,
        daysToTransplant: json['days_to_transplant'] as int? ?? 14,
      );

  Map<String, dynamic> toJson() => {
        'sow_months': sowMonths,
        'transplant_months': transplantMonths,
        'harvest_months': harvestMonths,
        'days_to_maturity': daysToMaturity,
        'days_to_transplant': daysToTransplant,
      };
}

class Plant {
  final String id;
  final String name;
  final String scientificName;
  final String category; // 'vegetable', 'herb', 'fruit', 'flower'
  final String description;
  final String? imageUrl;
  final PlantConditions conditions;
  final PlantSpacing spacing;
  final PlantTiming timing;
  final List<String> companionPlantIds;
  final List<String> incompatiblePlantIds;
  final double suitabilityScore; // 0.0 - 1.0
  final List<String> tags;
  final bool isNative;
  final String difficultyLevel; // 'easy', 'medium', 'hard'

  const Plant({
    required this.id,
    required this.name,
    required this.scientificName,
    required this.category,
    required this.description,
    this.imageUrl,
    required this.conditions,
    required this.spacing,
    required this.timing,
    this.companionPlantIds = const [],
    this.incompatiblePlantIds = const [],
    this.suitabilityScore = 0.8,
    this.tags = const [],
    this.isNative = false,
    this.difficultyLevel = 'easy',
  });

  static String? normalizeImageUrl(String? imageUrl) {
    if (imageUrl == null) return null;
    final normalized = imageUrl.trim();
    if (normalized.isEmpty) return null;

    // Reject HTML-page wiki URLs (not direct image links).
    // Reject Perenual paywall placeholder (returned when API tier lacks image access).
    final lower = normalized.toLowerCase();
    final isHtmlPage = (lower.contains('commons.wikimedia.org/wiki/') ||
        lower.contains('wikipedia.org/wiki/'));
    final isPaywallPlaceholder = lower.contains('upgrade_access');
    return (isHtmlPage || isPaywallPlaceholder) ? null : normalized;
  }

  factory Plant.fromJson(Map<String, dynamic> json) => Plant(
        id: json['id'] as String? ?? '',
        name: json['name'] as String,
        scientificName: json['scientific_name'] as String? ?? '',
        category: json['category'] as String? ?? 'ornamental',
        description: json['description'] as String? ?? '',
        imageUrl: normalizeImageUrl(json['image_url'] as String?),
        conditions: PlantConditions.fromJson(
            json['conditions'] as Map<String, dynamic>? ?? {}),
        spacing: PlantSpacing.fromJson(
            json['spacing'] as Map<String, dynamic>? ?? {}),
        timing: PlantTiming.fromJson(
            json['timing'] as Map<String, dynamic>? ?? {}),
        companionPlantIds:
            (json['companion_plant_ids'] as List<dynamic>? ?? [])
                .cast<String>(),
        incompatiblePlantIds:
            (json['incompatible_plant_ids'] as List<dynamic>? ?? [])
                .cast<String>(),
        suitabilityScore:
            (json['suitability_score'] as num? ?? 0.8).toDouble(),
        tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
        isNative: json['is_native'] as bool? ?? false,
        difficultyLevel: json['difficulty_level'] as String? ?? 'easy',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'scientific_name': scientificName,
        'category': category,
        'description': description,
        'image_url': imageUrl,
        'conditions': conditions.toJson(),
        'spacing': spacing.toJson(),
        'timing': timing.toJson(),
        'companion_plant_ids': companionPlantIds,
        'incompatible_plant_ids': incompatiblePlantIds,
        'suitability_score': suitabilityScore,
        'tags': tags,
        'is_native': isNative,
        'difficulty_level': difficultyLevel,
      };

  factory Plant.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Plant.fromJson({...data, 'id': doc.id});
  }

  Plant copyWith({
    String? id,
    String? name,
    String? scientificName,
    String? category,
    String? description,
    String? imageUrl,
    PlantConditions? conditions,
    PlantSpacing? spacing,
    PlantTiming? timing,
    List<String>? companionPlantIds,
    List<String>? incompatiblePlantIds,
    double? suitabilityScore,
    List<String>? tags,
    bool? isNative,
    String? difficultyLevel,
  }) {
    return Plant(
      id: id ?? this.id,
      name: name ?? this.name,
      scientificName: scientificName ?? this.scientificName,
      category: category ?? this.category,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      conditions: conditions ?? this.conditions,
      spacing: spacing ?? this.spacing,
      timing: timing ?? this.timing,
      companionPlantIds: companionPlantIds ?? this.companionPlantIds,
      incompatiblePlantIds: incompatiblePlantIds ?? this.incompatiblePlantIds,
      suitabilityScore: suitabilityScore ?? this.suitabilityScore,
      tags: tags ?? this.tags,
      isNative: isNative ?? this.isNative,
      difficultyLevel: difficultyLevel ?? this.difficultyLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Plant && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
