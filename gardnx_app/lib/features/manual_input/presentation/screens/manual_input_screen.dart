import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/core/utils/date_utils.dart';
import 'package:gardnx_app/features/climate/presentation/providers/location_provider.dart';
import 'package:gardnx_app/features/layout_planner/presentation/providers/recommendation_provider.dart';
import 'package:gardnx_app/features/layout_planner/presentation/screens/recommendation_screen.dart';
import 'package:gardnx_app/features/manual_input/domain/models/manual_bed.dart';
import 'package:gardnx_app/features/manual_input/presentation/providers/manual_input_provider.dart';
import 'package:gardnx_app/features/manual_input/presentation/widgets/bed_drawing_canvas.dart';
import 'package:gardnx_app/features/manual_input/presentation/widgets/sun_exposure_picker.dart';
import 'package:gardnx_app/shared/providers/firebase_providers.dart';

class ManualInputScreen extends ConsumerStatefulWidget {
  final String? gardenId;
  /// Optional path (local file or URL) to display as background behind drawn beds.
  final String? backgroundImagePath;
  /// Optional list of beds constructed from AI segmentation results
  final List<ManualBed>? initialBeds;

  const ManualInputScreen({
    super.key,
    this.gardenId,
    this.backgroundImagePath,
    this.initialBeds,
  });

  @override
  ConsumerState<ManualInputScreen> createState() => _ManualInputScreenState();
}

class _ManualInputScreenState extends ConsumerState<ManualInputScreen> {
  int _bedCounter = 0;

  /// Snapshot of beds loaded from Firestore for this garden, keyed by bed id.
  /// Used to diff against the current edit state on save so we can upsert
  /// correctly (add new / update changed / delete removed).
  final Map<String, ManualBed> _originalBeds = {};

  @override
  void initState() {
    super.initState();
    // Warm up location so the permission dialog appears early.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(currentLocationProvider.future).ignore();

      if (widget.initialBeds != null && widget.initialBeds!.isNotEmpty) {
        final notifier = ref.read(manualInputProvider.notifier);
        final initialBeds = widget.initialBeds!;
        notifier.setAll(initialBeds);
        _bedCounter = initialBeds.length;
        ref.read(selectedBedIdProvider.notifier).state = initialBeds.first.id;
        return;
      }

      // Editing an existing garden — hydrate from Firestore so the canvas
      // shows the beds the user previously drew.
      final gardenId = widget.gardenId;
      if (gardenId != null && gardenId.isNotEmpty) {
        final repo = ref.read(manualGardenRepositoryProvider);
        final beds = await repo.getBeds(gardenId);
        if (!mounted || beds.isEmpty) return;
        _originalBeds
          ..clear()
          ..addEntries(beds.map((b) => MapEntry(b.id, b)));
        ref.read(manualInputProvider.notifier).setAll(beds);
        _bedCounter = beds.length;
        ref.read(selectedBedIdProvider.notifier).state = beds.first.id;
      }
    });
  }

  @override
  void dispose() {
    // Reset the shared editing state so the next garden we open starts clean.
    Future.microtask(() {
      if (!mounted) {
        ref.invalidate(manualInputProvider);
        ref.invalidate(selectedBedIdProvider);
      }
    });
    super.dispose();
  }

  void _onBedDrawn(Rect rect) {
    _bedCounter++;
    final notifier = ref.read(manualInputProvider.notifier);
    notifier.addDrawnBed(rect: rect, index: _bedCounter);
    final beds = ref.read(manualInputProvider);
    if (beds.isNotEmpty) {
      ref.read(selectedBedIdProvider.notifier).state = beds.last.id;
      _showBedEditSheet(beds.last);
    }
  }

  void _onBedSelected(String bedId) {
    ref.read(selectedBedIdProvider.notifier).state = bedId;
    final bed = ref
        .read(manualInputProvider)
        .firstWhere((b) => b.id == bedId);
    _showBedEditSheet(bed);
  }

  void _onBedMoved(String bedId, Rect newRect) {
    final beds = ref.read(manualInputProvider);
    final bed = beds.firstWhere((b) => b.id == bedId);
    ref
        .read(manualInputProvider.notifier)
        .updateBed(bed.copyWith(rect: newRect));
  }

  Future<void> _showBedEditSheet(ManualBed bed) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BedEditSheet(
        bed: bed,
        onSave: (updated) {
          ref.read(manualInputProvider.notifier).updateBed(updated);
          Navigator.of(ctx).pop();
        },
        onDelete: () {
          ref.read(manualInputProvider.notifier).removeBed(bed.id);
          ref.read(selectedBedIdProvider.notifier).state = null;
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _onDone() async {
    final beds = ref.read(manualInputProvider);
    if (beds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw at least one garden bed first.')),
      );
      return;
    }

    // If no existing garden, ask for a name before creating one.
    String? gardenId = widget.gardenId;
    if (gardenId == null) {
      final name = await _askGardenName();
      if (name == null || !mounted) return;

      try {
        final user = ref.read(currentFirebaseUserProvider);
        final repo = ref.read(manualGardenRepositoryProvider);
        
        // Show fallback warning if needed
        final locationInfo = ref.read(currentLocationProvider).valueOrNull;
        if (locationInfo != null && locationInfo.isFallback) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Location Denied'),
              content: const Text(
                  'GardNx could not get your exact location. Plant recommendations will default to the North region. You can update this later in your profile.\n\nContinue anyway?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          if (proceed != true || !mounted) {
            return;
          }
        }
        
        final detectedRegion = locationInfo?.region ?? 'north';
        gardenId = await repo.createGarden(name, detectedRegion, user?.uid ?? '');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create garden: $e')),
          );
        }
        return;
      }
    }

    try {
      final repo = ref.read(manualGardenRepositoryProvider);
      final savedBeds = <ManualBed>[];
      final currentIds = beds.map((b) => b.id).toSet();

      // Delete beds that were loaded from Firestore but are no longer in
      // the edit state (user removed them).
      for (final originalId in _originalBeds.keys) {
        if (!currentIds.contains(originalId)) {
          await repo.removeBed(gardenId, originalId);
        }
      }

      for (final bed in beds) {
        final original = _originalBeds[bed.id];
        if (original == null) {
          // New bed — insert (Firestore assigns a real id).
          final saved = await repo.addBed(gardenId, bed);
          savedBeds.add(saved);
        } else {
          // Existing bed — update in place. ManualBed.== only compares id,
          // so we can't cheaply detect a no-op; the write is idempotent.
          await repo.updateBed(gardenId, bed);
          savedBeds.add(bed);
        }
      }
      await repo.updateGardenTimestamp(gardenId);

      if (!mounted) return;

      final season =
          MauritiusDateUtils.currentPrimarySeason().toLowerCase();
      final region = ref.read(currentLocationProvider).valueOrNull?.region
          ?? 'north';
      final resolvedGardenId = gardenId; // non-null guaranteed by flow above

      // Walk through every bed — user plans plants + layout for each in turn.
      // Returning from one bed loops back to the picker until all beds are
      // visited (or the user bails out).
      await _planBedsSequentially(
        beds: savedBeds,
        gardenId: resolvedGardenId,
        season: season,
        region: region,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save beds: $e')),
        );
      }
    }
  }

  Future<void> _planBedsSequentially({
    required List<ManualBed> beds,
    required String gardenId,
    required String season,
    required String region,
  }) async {
    final remaining = List<ManualBed>.of(beds);
    while (remaining.isNotEmpty && mounted) {
      final ManualBed? picked = remaining.length == 1
          ? remaining.first
          : await _pickBedToPlan(remaining);
      if (picked == null || !mounted) return;

      remaining.removeWhere((b) => b.id == picked.id);

      // Prime the recommendation engine for this specific bed.
      ref.read(recommendationParamsProvider.notifier).state =
          RecommendationParams(
        gardenId: gardenId,
        bedId: picked.id,
        widthCm: picked.widthCm,
        heightCm: picked.heightCm,
        sunExposure: picked.sunExposure,
        soilType: picked.soilType,
        season: season,
        region: region,
      );
      ref.read(selectedPlantsProvider.notifier).clear();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecommendationScreen(
            bed: picked,
            gardenId: gardenId,
            season: season,
            region: region,
          ),
        ),
      );

      if (!mounted) return;
      if (remaining.isEmpty) return;

      final continueNext = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Plan another bed?'),
          content: Text(
              '${remaining.length} bed(s) remaining. Plan another now, or come back later.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Next bed'),
            ),
          ],
        ),
      );
      if (continueNext != true) return;
    }
  }

  Future<ManualBed?> _pickBedToPlan(List<ManualBed> beds) async {
    return showModalBottomSheet<ManualBed>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Choose a bed to plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ...beds.map((b) => ListTile(
                  leading:
                      Icon(Icons.grid_view, color: b.color),
                  title: Text(b.name),
                  subtitle: Text(
                      '${b.widthCm.toStringAsFixed(0)}x${b.heightCm.toStringAsFixed(0)} cm  ·  ${b.sunExposureLabel}  ·  ${b.soilTypeLabel}'),
                  onTap: () => Navigator.pop(ctx, b),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _askGardenName() async {
    final controller = TextEditingController(text: 'My Garden');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name Your Garden'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Garden name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(
              ctx, v.trim().isEmpty ? 'My Garden' : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.pop(ctx, v.isEmpty ? 'My Garden' : v);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final beds = ref.watch(manualInputProvider);
    final selectedId = ref.watch(selectedBedIdProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Garden Beds'),
        actions: [
          if (beds.isNotEmpty)
            TextButton(
              onPressed: _onDone,
              child: const Text('Done'),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Drag to draw a bed. Tap a bed to edit it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (beds.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      ref.read(manualInputProvider.notifier).clear();
                      ref.read(selectedBedIdProvider.notifier).state = null;
                    },
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFF5F0E8),
              child: BedDrawingCanvas(
                beds: beds,
                selectedBedId: selectedId,
                onBedDrawn: _onBedDrawn,
                onBedSelected: _onBedSelected,
                onBedMoved: _onBedMoved,
              ),
            ),
          ),
          if (beds.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surface,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: beds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final bed = beds[index];
                  final isSelected = bed.id == selectedId;
                  return GestureDetector(
                    onTap: () => _onBedSelected(bed.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? bed.color.withOpacity(0.9)
                            : bed.color.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? Colors.amber
                              : bed.color.withOpacity(0.5),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        bed.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Drag on the canvas to draw a new bed'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        tooltip: 'Draw new bed',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BedEditSheet extends StatefulWidget {
  final ManualBed bed;
  final void Function(ManualBed updated) onSave;
  final VoidCallback onDelete;

  const _BedEditSheet({
    required this.bed,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_BedEditSheet> createState() => _BedEditSheetState();
}

class _BedEditSheetState extends State<_BedEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _notesController;
  late String _sunExposure;
  late String _soilType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.bed.name);
    _widthController =
        TextEditingController(text: widget.bed.widthCm.toStringAsFixed(0));
    _heightController =
        TextEditingController(text: widget.bed.heightCm.toStringAsFixed(0));
    _notesController = TextEditingController();
    _sunExposure = widget.bed.sunExposure;
    _soilType = widget.bed.soilType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final updated = widget.bed.copyWith(
      name: _nameController.text.trim().isEmpty
          ? widget.bed.name
          : _nameController.text.trim(),
      widthCm: double.tryParse(_widthController.text) ?? widget.bed.widthCm,
      heightCm:
          double.tryParse(_heightController.text) ?? widget.bed.heightCm,
      sunExposure: _sunExposure,
      soilType: _soilType,
    );
    widget.onSave(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Edit Bed', style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                  onPressed: widget.onDelete,
                  tooltip: 'Delete bed',
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Bed Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    decoration: const InputDecoration(
                      labelText: 'Width (cm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Sun Exposure', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SunExposurePicker(
              selectedValue: _sunExposure,
              onChanged: (v) => setState(() => _sunExposure = v),
            ),
            const SizedBox(height: 16),
            Text('Soil Type', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _soilType,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'loam', child: Text('Loam')),
                DropdownMenuItem(value: 'clay', child: Text('Clay')),
                DropdownMenuItem(value: 'sandy', child: Text('Sandy')),
                DropdownMenuItem(value: 'silt', child: Text('Silt')),
                DropdownMenuItem(value: 'peat', child: Text('Peat')),
                DropdownMenuItem(value: 'chalk', child: Text('Chalk')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _soilType = v);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Save Bed'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
