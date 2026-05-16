import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/garden_layout.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/plant_placement.dart';
import 'package:gardnx_app/features/layout_planner/data/repositories/layout_repository.dart';
import 'package:gardnx_app/core/network/api_client.dart';

final layoutRepositoryProvider = Provider<LayoutRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return LayoutRepository(dio: apiClient.dio);
});

class LayoutNotifier extends StateNotifier<GardenLayout?> {
  final LayoutRepository _repository;

  LayoutNotifier(this._repository) : super(null);

  void setLayout(GardenLayout layout) {
    state = layout;
  }

  void initEmpty({
    required String gardenId,
    required String bedId,
    required int rows,
    required int cols,
    double cellSizeCm = 30.0,
  }) {
    state = GardenLayout(
      gardenId: gardenId,
      bedId: bedId,
      gridRows: rows,
      gridCols: cols,
      cellSizeCm: cellSizeCm,
    );
  }

  /// Add a plant placement, checking for grid boundary and overlap.
  bool addPlacement(PlantPlacement placement) {
    final layout = state;
    if (layout == null) return false;

    // Check bounds
    if (placement.startRow + placement.rowSpan > layout.gridRows ||
        placement.startCol + placement.colSpan > layout.gridCols) {
      return false;
    }

    // Check overlap
    if (_hasOverlap(layout.placements, placement)) return false;

    state = layout.copyWith(
      placements: [...layout.placements, placement],
    );
    return true;
  }

  /// Move a placement to a new position.
  bool movePlacement(String placementId, int newRow, int newCol) {
    final layout = state;
    if (layout == null) return false;

    final index =
        layout.placements.indexWhere((p) => p.id == placementId);
    if (index == -1) return false;

    final existing = layout.placements[index];
    final updated = existing.copyWith(startRow: newRow, startCol: newCol);

    // Check bounds
    if (updated.startRow + updated.rowSpan > layout.gridRows ||
        updated.startCol + updated.colSpan > layout.gridCols) {
      return false;
    }

    // Check overlap (excluding self)
    final othersExcludingSelf =
        layout.placements.where((p) => p.id != placementId).toList();
    if (_hasOverlap(othersExcludingSelf, updated)) return false;

    final newPlacements = [...layout.placements];
    newPlacements[index] = updated;
    state = layout.copyWith(placements: newPlacements);
    return true;
  }

  /// Remove a placement by id.
  void removePlacement(String placementId) {
    final layout = state;
    if (layout == null) return;
    state = layout.copyWith(
      placements:
          layout.placements.where((p) => p.id != placementId).toList(),
    );
  }

  /// Clear all placements.
  void clearPlacements() {
    final layout = state;
    if (layout == null) return;
    state = layout.copyWith(placements: []);
  }

  bool _hasOverlap(
      List<PlantPlacement> existing, PlantPlacement candidate) {
    for (int r = candidate.startRow;
        r < candidate.startRow + candidate.rowSpan;
        r++) {
      for (int c = candidate.startCol;
          c < candidate.startCol + candidate.colSpan;
          c++) {
        for (final p in existing) {
          if (p.occupies(r, c)) return true;
        }
      }
    }
    return false;
  }

  Future<String?> saveCurrentLayout() async {
    final layout = state;
    if (layout == null) return null;
    try {
      final id = await _repository.saveLayout(layout);
      state = layout.copyWith(id: id);
      return id;
    } catch (_) {
      return null;
    }
  }
}

final layoutNotifierProvider =
    StateNotifierProvider<LayoutNotifier, GardenLayout?>(
  (ref) => LayoutNotifier(ref.read(layoutRepositoryProvider)),
);

// Selected placement id for highlighting
final selectedPlacementIdProvider = StateProvider<String?>((ref) => null);
