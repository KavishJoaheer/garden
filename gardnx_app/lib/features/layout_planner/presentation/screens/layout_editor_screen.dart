import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/calendar/domain/models/planting_event.dart';
import 'package:gardnx_app/features/calendar/domain/models/task.dart';
import 'package:gardnx_app/features/calendar/data/repositories/calendar_repository.dart';
import 'package:gardnx_app/features/calendar/presentation/providers/calendar_provider.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/garden_layout.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/layout_suggestion.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/plant_placement.dart';
import 'package:gardnx_app/features/layout_planner/presentation/providers/layout_provider.dart';
import 'package:gardnx_app/features/layout_planner/presentation/widgets/companion_indicator.dart';
import 'package:gardnx_app/features/layout_planner/presentation/widgets/garden_grid_painter.dart';
import 'package:gardnx_app/features/layout_planner/presentation/widgets/plant_palette.dart';
import 'package:gardnx_app/features/layout_planner/presentation/widgets/spacing_guide.dart';
import 'package:gardnx_app/features/manual_input/domain/models/manual_bed.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';
import 'package:gardnx_app/features/plant_database/presentation/providers/plant_provider.dart';
import 'package:gardnx_app/shared/providers/firebase_providers.dart';

class LayoutEditorScreen extends ConsumerStatefulWidget {
  final ManualBed bed;
  final String gardenId;
  final String season;
  final String region;
  final List<String> selectedPlantIds;

  const LayoutEditorScreen({
    super.key,
    required this.bed,
    required this.gardenId,
    required this.season,
    required this.region,
    required this.selectedPlantIds,
  });

  @override
  ConsumerState<LayoutEditorScreen> createState() =>
      _LayoutEditorScreenState();
}

class _LayoutEditorScreenState extends ConsumerState<LayoutEditorScreen> {
  bool _isGenerating = false;
  bool _isSaving = false;

  Timer? _validateDebounce;
  List<LayoutWarning> _warnings = const [];
  int _validateSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLayout();
      _autoGenerate();
    });
  }

  @override
  void dispose() {
    _validateDebounce?.cancel();
    super.dispose();
  }

  void _scheduleValidation() {
    _validateDebounce?.cancel();
    _validateDebounce = Timer(const Duration(milliseconds: 300), _runValidation);
  }

  Future<void> _runValidation() async {
    final layout = ref.read(layoutNotifierProvider);
    if (layout == null || layout.placements.length < 2) {
      if (mounted && _warnings.isNotEmpty) setState(() => _warnings = const []);
      return;
    }
    final mySeq = ++_validateSeq;
    try {
      final repo = ref.read(layoutRepositoryProvider);
      final warnings = await repo.validateLayout(
        layout: layout,
        bedWidthCm: widget.bed.widthCm,
        bedHeightCm: widget.bed.heightCm,
        sunExposure: widget.bed.sunExposure,
      );
      if (!mounted || mySeq != _validateSeq) return;
      setState(() => _warnings = warnings);
    } catch (_) {
      // Validation is best-effort — keep prior warnings on failure.
    }
  }

  void _initLayout() {
    final cellSize = 30.0;
    final rows =
        (widget.bed.heightCm / cellSize).floor().clamp(1, 20);
    final cols =
        (widget.bed.widthCm / cellSize).floor().clamp(1, 20);
    ref.read(layoutNotifierProvider.notifier).initEmpty(
          gardenId: widget.gardenId,
          bedId: widget.bed.id,
          rows: rows,
          cols: cols,
          cellSizeCm: cellSize,
        );
  }

  Future<void> _autoGenerate() async {
    setState(() => _isGenerating = true);
    try {
      final repo = ref.read(layoutRepositoryProvider);
      GardenLayout layout = await repo.generateLayout(
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
        widthCm: widget.bed.widthCm,
        heightCm: widget.bed.heightCm,
        selectedPlantIds: widget.selectedPlantIds,
        sunExposure: widget.bed.sunExposure,
        season: widget.season,
      );

      // Backend does not echo gardenId/bedId — always restore them.
      layout = layout.copyWith(
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
      );

      // If the backend returned no placements (offline / poor result),
      // fall back to a client-side distribution algorithm.
      if (layout.placements.isEmpty) {
        layout = _generateLocalLayout(layout);
      }

      ref.read(layoutNotifierProvider.notifier).setLayout(layout);
      _scheduleValidation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not auto-generate: $e'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// Distributes [widget.selectedPlantIds] evenly across [base]'s grid by
  /// giving each plant a proportional slice of columns, then filling that
  /// slice row-by-row respecting the plant's spacing requirement.
  GardenLayout _generateLocalLayout(GardenLayout base) {
    final allPlants = ref.read(allPlantsProvider).value ?? [];
    final selected = allPlants
        .where((p) => widget.selectedPlantIds.contains(p.id))
        .toList();
    if (selected.isEmpty) return base;

    final rows = base.gridRows;
    final cols = base.gridCols;
    final n = selected.length;
    final colsPerPlant = (cols / n).ceil().clamp(1, cols);
    final placements = <PlantPlacement>[];

    for (int pi = 0; pi < n; pi++) {
      final plant = selected[pi];
      final span = plant.spacing.gridCellsRequired > 1 ? 2 : 1;
      final startCol = pi * colsPerPlant;
      final endCol = ((pi + 1) * colsPerPlant).clamp(0, cols);
      if (startCol >= cols) break;

      for (int r = 0; r + span <= rows; r += span) {
        for (int c = startCol; c + span <= endCol; c += span) {
          placements.add(PlantPlacement(
            id: '${plant.id}_${r}_$c',
            plantId: plant.id,
            plantName: plant.name,
            startRow: r,
            startCol: c,
            rowSpan: span,
            colSpan: span,
          ));
        }
      }
    }

    return base.copyWith(placements: placements);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final layoutId = await ref
          .read(layoutNotifierProvider.notifier)
          .saveCurrentLayout();
      if (!mounted) return;
      if (layoutId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Layout saved!')),
        );
        // Make the calendar tab aware of this garden immediately.
        ref.read(activeGardenIdProvider.notifier).state = widget.gardenId;
        // Fire-and-forget: generate calendar in the background.
        _generateAndSaveCalendar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to save layout. Please try again.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save layout.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _generateAndSaveCalendar() async {
    final layout = ref.read(layoutNotifierProvider);
    if (layout == null || layout.placements.isEmpty) return;

    // Collect unique plant IDs and names from placements.
    final Map<String, String> placementPlantNames = {};
    for (final p in layout.placements) {
      placementPlantNames[p.plantId] = p.plantName;
    }

    // Try to resolve full Plant objects for timing data.
    // Match by ID first; fall back to matching by name.
    // Use .future so we wait for the provider to load rather than getting null.
    final allPlants = await ref.read(allPlantsProvider.future).catchError((_) => <Plant>[]);
    final plants = <Plant>[];
    for (final entry in placementPlantNames.entries) {
      Plant? found = allPlants.where((p) => p.id == entry.key).firstOrNull;
      found ??= allPlants
          .where((p) =>
              p.name.toLowerCase() == entry.value.toLowerCase())
          .firstOrNull;
      if (found != null) plants.add(found);
    }

    // If we can't resolve any Plant objects, generate simple tasks locally.
    if (plants.isEmpty) {
      _saveLocalCalendarTasks(placementPlantNames);
      return;
    }

    try {
      final calRepo = ref.read(calendarRepositoryProvider);

      final events = await calRepo.generateCalendar(
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
        bedName: widget.bed.name,
        region: widget.region,
        plants: plants,
      );

      // If backend returned no events, fall back to local generation.
      final effectiveEvents = events.isNotEmpty
          ? events
          : _buildLocalEvents(plants);

      final tasks = effectiveEvents.map((e) {
        final daysUntil =
            e.date.difference(DateTime.now()).inDays;
        final priority =
            daysUntil <= 7 ? 'high' : (daysUntil <= 30 ? 'medium' : 'low');
        return PlantingTask(
          id: CalendarRepository.stableTaskId(
              bedId: widget.bed.id,
              plantId: e.plantId,
              type: e.eventType.value,
              date: e.date),
          gardenId: widget.gardenId,
          bedId: widget.bed.id,
          plantId: e.plantId,
          plantName: e.plantName,
          description:
              e.notes ?? '${e.eventType.label}: ${e.plantName}',
          dueDate: e.date,
          taskType: e.eventType.value,
          priority: priority,
        );
      }).toList();

      final uid = ref.read(currentFirebaseUserProvider)?.uid ?? '';
      if (uid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in to save your calendar.')),
          );
        }
        return;
      }
      final plantIds = plants.map((p) => p.id).toList();
      await calRepo.replaceEventsForBed(
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
        plantIds: plantIds,
        events: effectiveEvents,
        uid: uid,
      );
      await calRepo.replaceTasksForBed(
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
        plantIds: plantIds,
        tasks: tasks,
        uid: uid,
      );
      ref.invalidate(gardenEventsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Planting calendar updated!')),
        );
      }
    } catch (_) {
      // Calendar generation is best-effort; try local fallback.
      _saveLocalCalendarTasks(placementPlantNames);
    }
  }

  /// Builds PlantingEvents from Plant timing data without a backend call.
  List<PlantingEvent> _buildLocalEvents(List<Plant> plants) {
    final now = DateTime.now();
    final events = <PlantingEvent>[];
    for (final plant in plants) {
      // Sow event: next sow month, or 2 weeks from now if unknown.
      final nextSow = plant.timing.sowMonths.isNotEmpty
          ? _nextMonthDate(plant.timing.sowMonths, now)
          : now.add(const Duration(days: 14));
      events.add(PlantingEvent(
        id: CalendarRepository.stableEventId(
            bedId: widget.bed.id,
            plantId: plant.id,
            type: PlantingEventType.sow.value,
            date: nextSow),
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
        plantId: plant.id,
        plantName: plant.name,
        eventType: PlantingEventType.sow,
        date: nextSow,
        notes: 'Time to sow ${plant.name}',
        isCompleted: false,
      ));

      // Harvest event: days to maturity after sow.
      if (plant.timing.daysToMaturity > 0) {
        final harvestDate = nextSow.add(Duration(days: plant.timing.daysToMaturity));
        events.add(PlantingEvent(
          id: CalendarRepository.stableEventId(
              bedId: widget.bed.id,
              plantId: plant.id,
              type: PlantingEventType.harvest.value,
              date: harvestDate),
          gardenId: widget.gardenId,
          bedId: widget.bed.id,
          plantId: plant.id,
          plantName: plant.name,
          eventType: PlantingEventType.harvest,
          date: harvestDate,
          notes: 'Harvest ${plant.name}',
          isCompleted: false,
        ));
      }
    }
    return events;
  }

  /// Returns the next calendar date whose month is in [months].
  DateTime _nextMonthDate(List<int> months, DateTime from) {
    for (int offset = 0; offset < 12; offset++) {
      final candidate =
          DateTime(from.year, from.month + offset, 1);
      if (months.contains(candidate.month)) {
        return DateTime(candidate.year, candidate.month, 15);
      }
    }
    return from.add(const Duration(days: 30));
  }

  /// Last-resort: save bare tasks AND events using only placement plant names.
  /// Events are needed so CalendarScreen's date markers appear; tasks show in
  /// the task list.
  Future<void> _saveLocalCalendarTasks(
      Map<String, String> plantNames) async {
    try {
      final calRepo = ref.read(calendarRepositoryProvider);
      final sowDate = DateTime.now().add(const Duration(days: 14));

      final events = plantNames.entries.map((e) {
        return PlantingEvent(
          id: CalendarRepository.stableEventId(
              bedId: widget.bed.id,
              plantId: e.key,
              type: PlantingEventType.sow.value,
              date: sowDate),
          gardenId: widget.gardenId,
          bedId: widget.bed.id,
          plantId: e.key,
          plantName: e.value,
          eventType: PlantingEventType.sow,
          date: sowDate,
          notes: 'Time to sow ${e.value} in ${widget.bed.name}',
          isCompleted: false,
        );
      }).toList();

      final tasks = plantNames.entries.map((e) {
        return PlantingTask(
          id: CalendarRepository.stableTaskId(
              bedId: widget.bed.id,
              plantId: e.key,
              type: 'sow',
              date: sowDate),
          gardenId: widget.gardenId,
          bedId: widget.bed.id,
          plantId: e.key,
          plantName: e.value,
          description: 'Sow ${e.value} in ${widget.bed.name}',
          dueDate: sowDate,
          taskType: 'sow',
          priority: 'medium',
        );
      }).toList();

      final uid = ref.read(currentFirebaseUserProvider)?.uid ?? '';
      if (uid.isEmpty) return;
      final plantIds = plantNames.keys.toList();
      await calRepo.replaceEventsForBed(
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
        plantIds: plantIds,
        events: events,
        uid: uid,
      );
      await calRepo.replaceTasksForBed(
        gardenId: widget.gardenId,
        bedId: widget.bed.id,
        plantIds: plantIds,
        tasks: tasks,
        uid: uid,
      );
      ref.invalidate(gardenEventsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Planting reminders added to calendar!')),
        );
      }
    } catch (e) {
      debugPrint('_saveLocalCalendarTasks failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calendar save failed: $e')),
        );
      }
    }
  }

  void _showPlantPalette() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PlantPalette(
        onPlantSelected: (plant) {
          Navigator.of(context).pop();
          _addPlantToGrid(plant);
        },
      ),
    );
  }

  void _addPlantToGrid(Plant plant) {
    final layout = ref.read(layoutNotifierProvider);
    if (layout == null) return;

    for (int r = 0; r < layout.gridRows; r++) {
      for (int c = 0; c < layout.gridCols; c++) {
        bool occupied = false;
        for (final p in layout.placements) {
          if (p.occupies(r, c)) {
            occupied = true;
            break;
          }
        }
        if (!occupied) {
          final placement = PlantPlacement(
            id: '${plant.id}_${r}_$c',
            plantId: plant.id,
            plantName: plant.name,
            startRow: r,
            startCol: c,
            rowSpan: plant.spacing.gridCellsRequired > 1 ? 2 : 1,
            colSpan: plant.spacing.gridCellsRequired > 1 ? 2 : 1,
          );
          final added =
              ref.read(layoutNotifierProvider.notifier).addPlacement(placement);
          if (!added && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No space available for this plant.')),
            );
          }
          return;
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Grid is full!')),
    );
  }

  void _showPlantSchedule(GardenLayout layout) {
    final allPlants = ref.read(allPlantsProvider).value ?? [];

    // Unique plants in the layout (de-duplicated by plantId).
    final Map<String, String> idToName = {};
    for (final p in layout.placements) {
      idToName[p.plantId] = p.plantName;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (_, controller) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text('When to Plant',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: idToName.entries.map((entry) {
                    final plant = allPlants
                        .where((p) =>
                            p.id == entry.key ||
                            p.name.toLowerCase() ==
                                entry.value.toLowerCase())
                        .firstOrNull;
                    return _PlantScheduleCard(
                      plantName: entry.value,
                      plant: plant,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GardenLayout?>(layoutNotifierProvider, (prev, next) {
      if (!identical(prev?.placements, next?.placements)) {
        _scheduleValidation();
      }
    });

    final layout = ref.watch(layoutNotifierProvider);
    final selectedId = ref.watch(selectedPlacementIdProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bed.name),
        actions: [
          if (layout != null && layout.placements.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => _showPlantSchedule(layout),
              tooltip: 'When to plant',
            ),
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.save_outlined),
                    onPressed: _save,
                    tooltip: 'Save layout',
                  ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Grid
          Expanded(
            child: layout == null
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: GardenGridWidget(
                      layout: layout,
                      selectedPlacementId: selectedId,
                      onPlacementTap: (id) {
                        ref.read(selectedPlacementIdProvider.notifier).state =
                            selectedId == id ? null : id;
                      },
                      onCellTap: (row, col) {
                        ref.read(selectedPlacementIdProvider.notifier).state =
                            null;
                      },
                    ),
                  ),
          ),

          // Bottom panel
          if (layout != null) ...[
            if (_warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _warnings
                        .take(3)
                        .map((w) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: CompanionIndicator(
                                type: CompanionIndicatorType.incompatible,
                                text: w.message,
                                compact: true,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SpacingGuide(layout: layout),
            ),
            if (selectedId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove selected plant'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    onPressed: () {
                      ref
                          .read(layoutNotifierProvider.notifier)
                          .removePlacement(selectedId);
                      ref.read(selectedPlacementIdProvider.notifier).state =
                          null;
                    },
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'palette',
            onPressed: _showPlantPalette,
            tooltip: 'Add plant',
            child: const Icon(Icons.local_florist),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'generate',
            onPressed: _isGenerating ? null : _autoGenerate,
            icon: _isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high),
            label: const Text('Auto-Generate'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plant schedule card widget
// ---------------------------------------------------------------------------

class _PlantScheduleCard extends StatelessWidget {
  final String plantName;
  final Plant? plant;

  const _PlantScheduleCard({required this.plantName, this.plant});

  static const _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _months(List<int> months) =>
      months.isEmpty ? '—' : months.map((m) => _monthNames[m]).join(', ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final emoji = PlantEmojiMap.get(plantName);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Text(
                  plantName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (plant == null) ...[
              const SizedBox(height: 6),
              Text(
                'Timing data not available locally.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ] else ...[
              const SizedBox(height: 8),
              _Row(
                icon: Icons.grass,
                color: Colors.green,
                label: 'Sow',
                value: _months(plant!.timing.sowMonths),
              ),
              if (plant!.timing.transplantMonths.isNotEmpty)
                _Row(
                  icon: Icons.swap_horiz,
                  color: Colors.orange,
                  label: 'Transplant',
                  value: _months(plant!.timing.transplantMonths),
                ),
              _Row(
                icon: Icons.cut,
                color: Colors.red,
                label: 'Harvest',
                value: _months(plant!.timing.harvestMonths),
              ),
              _Row(
                icon: Icons.timer_outlined,
                color: colorScheme.primary,
                label: 'Days to harvest',
                value: '${plant!.timing.daysToMaturity} days',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _Row({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
