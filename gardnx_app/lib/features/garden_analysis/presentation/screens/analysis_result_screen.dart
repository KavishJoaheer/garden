import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../manual_input/domain/models/manual_bed.dart';
import '../../../manual_input/presentation/screens/manual_input_screen.dart';
import '../../domain/models/garden_photo.dart';
import '../providers/analysis_provider.dart';
import '../widgets/segmentation_overlay.dart';
import '../widgets/zone_legend.dart';

/// Screen showing the analysis result with segmentation overlay.
///
/// Users can tap zones to select/deselect them, view a legend, switch to
/// manual mode, or continue with the selected zones.
class AnalysisResultScreen extends ConsumerStatefulWidget {
  final GardenPhoto photo;

  const AnalysisResultScreen({super.key, required this.photo});

  static const routeName = '/garden/analyze';

  @override
  ConsumerState<AnalysisResultScreen> createState() =>
      _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends ConsumerState<AnalysisResultScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger segmentation analysis.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(segmentationProvider.notifier)
          .analyzePhoto(widget.photo.id);
    });
  }

  void _handleZoneTap(String zoneId) {
    ref.read(selectedZonesProvider.notifier).toggleZone(zoneId);
  }

  void _handleSelectAll() {
    final segState = ref.read(segmentationProvider);
    if (segState.result != null) {
      final allIds = segState.result!.zones.map((z) => z.zoneId).toList();
      ref.read(selectedZonesProvider.notifier).selectAll(allIds);
    }
  }

  void _handleClearSelection() {
    ref.read(selectedZonesProvider.notifier).clearSelection();
  }

  void _handleContinue() {
    final selectedZonesSet = ref.read(selectedZonesProvider);
    if (selectedZonesSet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one zone to continue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Convert selected GardenZones to ManualBeds using bounding boxes
    final segState = ref.read(segmentationProvider);
    if (segState.result == null) return;

    final selectedZones = segState.result!.zones
        .where((z) => selectedZonesSet.contains(z.zoneId))
        .toList();

    final initialBeds = <ManualBed>[];
    int bedCounter = 1;

    for (final zone in selectedZones) {
      if (zone.polygon.isEmpty) continue;

      // Calculate bounding box from polygon points
      double minX = zone.polygon.first.dx;
      double maxX = zone.polygon.first.dx;
      double minY = zone.polygon.first.dy;
      double maxY = zone.polygon.first.dy;

      for (final point in zone.polygon) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }

      // Convert from relative screen coordinates (0.0 - 1.0) 
      // to typical canvas logical pixels. We assume a standard 300x300 canvas size 
      // as a baseline, but the canvas scales.
      final rect = Rect.fromLTRB(
        minX * 300,
        minY * 300,
        maxX * 300,
        maxY * 300,
      );

      initialBeds.add(
        ManualBed(
          id: zone.zoneId,
          name: '${zone.displayLabel} Bed $bedCounter',
          widthCm: (maxX - minX) * 500, // rough assumption of 5m full width
          heightCm: (maxY - minY) * 500,
          sunExposure: _mapTypeToSunExposure(zone.type),
          rect: rect,
          color: zone.color,
        ),
      );
      bedCounter++;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ManualInputScreen(
          backgroundImagePath: widget.photo.localPath ?? widget.photo.imageUrl,
          initialBeds: initialBeds,
        ),
      ),
    );
  }

  String _mapTypeToSunExposure(String type) {
    switch (type.toLowerCase()) {
      case 'shade':
      case 'shaded':
        return 'full_shade';
      case 'sun':
      case 'sunny':
      case 'full_sun':
        return 'full_sun';
      default:
        return 'partial_shade'; // Default fallback assumption
    }
  }

  void _navigateToManual() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ManualInputScreen(
          backgroundImagePath: widget.photo.localPath ?? widget.photo.imageUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segState = ref.watch(segmentationProvider);
    final selectedZones = ref.watch(selectedZonesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Result'),
        actions: [
          if (segState.result != null) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select All',
              onPressed: _handleSelectAll,
            ),
            IconButton(
              icon: const Icon(Icons.deselect),
              tooltip: 'Clear Selection',
              onPressed: _handleClearSelection,
            ),
          ],
        ],
      ),
      body: _buildBody(segState, selectedZones),
      bottomNavigationBar: segState.result != null
          ? _buildBottomBar(segState, selectedZones)
          : null,
    );
  }

  Widget _buildBody(
    SegmentationState segState,
    Set<String> selectedZones,
  ) {
    // Loading state
    if (segState.isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text(
              'Analyzing your garden...',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            SizedBox(height: 8),
            Text(
              'This may take a few seconds',
              style: TextStyle(color: AppColors.textHint),
            ),
          ],
        ),
      );
    }

    // Error state
    if (segState.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Analysis Failed',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                segState.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  ref
                      .read(segmentationProvider.notifier)
                      .analyzePhoto(widget.photo.id);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Analysis'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _navigateToManual,
                icon: const Icon(Icons.edit),
                label: const Text('Use Manual Mode'),
              ),
            ],
          ),
        ),
      );
    }

    // Result state
    if (segState.result == null) {
      return const Center(child: Text('No results available.'));
    }

    final result = segState.result!;

    return Column(
      children: [
        // ----- Photo with overlay -----
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background photo
              if (widget.photo.localPath != null)
                Image.file(
                  File(widget.photo.localPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image, size: 64),
                  ),
                )
              else if (widget.photo.imageUrl != null)
                Image.network(
                  widget.photo.imageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image, size: 64),
                  ),
                )
              else
                Container(
                  color: AppColors.surfaceVariant,
                  child: const Center(
                    child: Icon(Icons.image_not_supported, size: 64),
                  ),
                ),

              // Segmentation overlay — photoPath lets it resolve the image's
              // intrinsic size so zone polygons align with BoxFit.contain.
              SegmentationOverlay(
                zones: result.zones,
                selectedZoneIds: selectedZones,
                onZoneTap: _handleZoneTap,
                photoPath: widget.photo.localPath ?? widget.photo.imageUrl,
              ),

              // Fallback recommendation banner
              if (result.fallbackRecommended)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Card(
                    color: AppColors.warningContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Low confidence analysis. Manual mode recommended.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: _navigateToManual,
                            child: const Text(
                              'Manual',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ----- Zone legend -----
        ZoneLegend(zones: result.zones, selectedZoneIds: selectedZones),

        // ----- Selection info -----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${selectedZones.length} zone${selectedZones.length == 1 ? '' : 's'} selected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Text(
                'Tap zones to select/deselect',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textHint,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(
    SegmentationState segState,
    Set<String> selectedZones,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _navigateToManual,
                icon: const Icon(Icons.edit),
                label: const Text('Manual Mode'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: selectedZones.isEmpty
                    ? null
                    : _handleContinue,
                icon: const Icon(Icons.check),
                label: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
