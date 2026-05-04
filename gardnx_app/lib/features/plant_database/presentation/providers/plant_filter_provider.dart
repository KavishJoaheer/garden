import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant_filter.dart';
import 'package:gardnx_app/features/plant_database/presentation/providers/plant_provider.dart';
import 'package:gardnx_app/features/profile/presentation/providers/profile_provider.dart';

class PlantFilterNotifier extends StateNotifier<PlantFilter> {
  PlantFilterNotifier() : super(const PlantFilter());

  void setSearchQuery(String query) {
    if (query.isEmpty) {
      state = state.clearSearch();
    } else {
      state = state.copyWith(searchQuery: query);
    }
  }

  void toggleCategory(String category) {
    final current = List<String>.from(state.categories);
    if (current.contains(category)) {
      current.remove(category);
    } else {
      current.add(category);
    }
    state = state.copyWith(categories: current);
  }

  void toggleSunRequirement(String sun) {
    final current = List<String>.from(state.sunRequirements);
    if (current.contains(sun)) {
      current.remove(sun);
    } else {
      current.add(sun);
    }
    state = state.copyWith(sunRequirements: current);
  }

  void toggleWaterNeed(String water) {
    final current = List<String>.from(state.waterNeeds);
    if (current.contains(water)) {
      current.remove(water);
    } else {
      current.add(water);
    }
    state = state.copyWith(waterNeeds: current);
  }

  void toggleDifficulty(String difficulty) {
    final current = List<String>.from(state.difficultyLevels);
    if (current.contains(difficulty)) {
      current.remove(difficulty);
    } else {
      current.add(difficulty);
    }
    state = state.copyWith(difficultyLevels: current);
  }

  void setMinSuitability(double? score) {
    state = state.copyWith(minSuitabilityScore: score);
  }

  void setNativeOnly(bool? value) {
    state = state.copyWith(isNativeOnly: value);
  }

  /// Apply the user's preferred plant types as the initial category filter.
  /// Does nothing when types is empty or all types are selected (no restriction).
  void applyPreferenceDefaults(List<String> preferredTypes) {
    // Only apply if the user has no manual filter yet.
    if (state.categories.isNotEmpty) return;
    if (preferredTypes.isEmpty) return;
    state = state.copyWith(categories: List<String>.from(preferredTypes));
  }

  /// Clears all category filters so every plant type is shown.
  /// Used by the 'Show all' banner when the user's profile preferences
  /// are acting as a soft default filter.
  void showAll() {
    state = state.copyWith(categories: []);
  }

  void reset() {
    state = const PlantFilter();
  }
}

final plantFilterProvider =
    StateNotifierProvider<PlantFilterNotifier, PlantFilter>(
  (ref) => PlantFilterNotifier(),
);

/// Derived provider: all plants filtered by current filter state.
///
/// Also respects the user's plant-type preferences from their profile —
/// if the user set preferred types and hasn't manually chosen a category
/// filter yet, those preferences act as the default filter. A "Show All"
/// button in the UI (or clearing the filter) can override this.
final filteredPlantsProvider = Provider<AsyncValue<List<Plant>>>((ref) {
  final filter = ref.watch(plantFilterProvider);
  final allAsync = ref.watch(allPlantsProvider);

  // Read profile preferences to apply as defaults (non-blocking).
  final profile = ref.watch(currentUserProfileProvider).asData?.value;
  final preferredTypes = profile?.preferences.plantTypes ?? const <String>[];

  // Soft default: apply preference categories only when the user has set
  // preferences and hasn't manually chosen a category filter.
  PlantFilter effectiveFilter = filter;
  if (filter.categories.isEmpty && preferredTypes.isNotEmpty) {
    effectiveFilter = filter.copyWith(categories: preferredTypes);
  }

  return allAsync.when(
    data: (plants) => AsyncData(effectiveFilter.apply(plants)),
    loading: () => const AsyncLoading(),
    error: (e, st) => AsyncError(e, st),
  );
});

/// Whether the catalog is currently filtered by user preferences
/// (rather than a manual filter). Used to show the "Filtered by preferences"
/// hint in the UI.
final isFilteredByPreferencesProvider = Provider<bool>((ref) {
  final filter = ref.watch(plantFilterProvider);
  final profile = ref.watch(currentUserProfileProvider).asData?.value;
  final preferredTypes = profile?.preferences.plantTypes ?? const <String>[];
  // True when: no manual filter AND user has preferences set.
  return filter.categories.isEmpty && preferredTypes.isNotEmpty;
});

/// Active filter count (for badge display).
/// Counts manual filters only (not preference-defaults).
final activeFilterCountProvider = Provider<int>((ref) {
  final filter = ref.watch(plantFilterProvider);
  int count = 0;
  if (filter.categories.isNotEmpty) count++;
  if (filter.sunRequirements.isNotEmpty) count++;
  if (filter.waterNeeds.isNotEmpty) count++;
  if (filter.difficultyLevels.isNotEmpty) count++;
  if (filter.minSuitabilityScore != null) count++;
  if (filter.isNativeOnly == true) count++;
  return count;
});
