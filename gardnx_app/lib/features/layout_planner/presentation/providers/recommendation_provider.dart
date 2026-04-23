import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/layout_planner/data/repositories/layout_repository.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/layout_suggestion.dart';
import 'package:gardnx_app/features/layout_planner/presentation/providers/layout_provider.dart';
import 'package:gardnx_app/features/plant_database/presentation/providers/plant_provider.dart';
import 'package:gardnx_app/features/profile/presentation/providers/profile_provider.dart';

// Parameters passed to the recommendation request
class RecommendationParams {
  final String gardenId;
  final String bedId;
  final double widthCm;
  final double heightCm;
  final String sunExposure;
  final String soilType;
  final String season;
  final String region;

  const RecommendationParams({
    required this.gardenId,
    required this.bedId,
    required this.widthCm,
    required this.heightCm,
    required this.sunExposure,
    required this.soilType,
    required this.season,
    required this.region,
  });
}

final recommendationParamsProvider =
    StateProvider<RecommendationParams?>((ref) => null);

// 'gemini', 'ollama', 'rules', or null (auto)
final enginePreferenceProvider = StateProvider<String?>((ref) => null);

final engineUsedProvider = StateProvider<String?>((ref) => null);
final engineRequestedProvider = StateProvider<String?>((ref) => null);
final fallbackReasonProvider = StateProvider<String?>((ref) => null);

final engineStatusProvider = FutureProvider<Map<String, EngineStatus>>((ref) async {
  final repo = ref.read(layoutRepositoryProvider);
  return repo.getEngineStatus();
});

final recommendationsProvider =
    FutureProvider<List<LayoutSuggestion>>((ref) async {
  final params = ref.watch(recommendationParamsProvider);
  if (params == null) return [];

  final preferredEngine = ref.watch(enginePreferenceProvider);
  final repo = ref.read(layoutRepositoryProvider);

  // Source preferences + experience level from the signed-in user's profile.
  final profile = ref.watch(currentUserProfileProvider).asData?.value;
  final preferences = profile?.preferences.plantTypes ?? const <String>[];
  final experienceLevel = profile?.preferences.experienceLevel;

  final result = await repo.getRecommendations(
    gardenId: params.gardenId,
    bedId: params.bedId,
    widthCm: params.widthCm,
    heightCm: params.heightCm,
    sunExposure: params.sunExposure,
    soilType: params.soilType,
    season: params.season,
    region: params.region,
    preferences: preferences,
    experienceLevel: experienceLevel,
    preferredEngine: preferredEngine,
  );

  ref.read(engineRequestedProvider.notifier).state = result.engineRequested;
  ref.read(fallbackReasonProvider.notifier).state = result.fallbackReason;

  if (result.suggestions.isNotEmpty) {
    ref.read(engineUsedProvider.notifier).state = result.engineUsed;
    return result.suggestions;
  }

  ref.read(engineUsedProvider.notifier).state = 'local-rules';
  // Backend unavailable — build recommendations from bundled plant data.
  return _localRecommendations(ref, params);
});

Future<List<LayoutSuggestion>> _localRecommendations(
  Ref ref,
  RecommendationParams params,
) async {
  final plants = await ref.read(allPlantsProvider.future);
  final month = DateTime.now().month;
  final suggestions = <LayoutSuggestion>[];

  for (final plant in plants) {
    double score = plant.suitabilityScore;
    final reasons = <String>[];

    if (plant.conditions.sunRequirement == params.sunExposure) {
      score = (score + 0.10).clamp(0.0, 1.0);
      reasons.add('Suits ${params.sunExposure.replaceAll('_', ' ')}');
    }
    if (plant.timing.sowMonths.contains(month)) {
      score = (score + 0.10).clamp(0.0, 1.0);
      reasons.add('Good planting season right now');
    }
    if (plant.conditions.suitableSoils.contains(params.soilType) ||
        plant.conditions.suitableSoils.any((s) => s.contains('loam'))) {
      score = (score + 0.05).clamp(0.0, 1.0);
    }

    if (score < 0.35) continue;

    final bedArea = params.widthCm * params.heightCm;
    final spacing = plant.spacing.plantSpacingCm * plant.spacing.rowSpacingCm;
    final maxCount =
        (bedArea / (spacing > 0 ? spacing : 900)).floor().clamp(1, 20);

    suggestions.add(LayoutSuggestion(
      plantId: plant.id,
      plantName: plant.name,
      suitabilityScore: score,
      reasons: reasons.isEmpty ? ['Suitable for Mauritius climate'] : reasons,
      maxCount: maxCount,
    ));
  }

  suggestions.sort((a, b) => b.suitabilityScore.compareTo(a.suitabilityScore));
  return suggestions.take(15).toList();
}

// StateNotifier for the user-selected plants list
class SelectedPlantsNotifier extends StateNotifier<Set<String>> {
  SelectedPlantsNotifier() : super({});

  void toggle(String plantId) {
    if (state.contains(plantId)) {
      state = {...state}..remove(plantId);
    } else {
      state = {...state, plantId};
    }
  }

  void selectAll(List<String> ids) {
    state = Set<String>.from(ids);
  }

  void clear() {
    state = {};
  }

  bool isSelected(String plantId) => state.contains(plantId);
}

final selectedPlantsProvider =
    StateNotifierProvider<SelectedPlantsNotifier, Set<String>>(
  (ref) => SelectedPlantsNotifier(),
);
