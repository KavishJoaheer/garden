import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/layout_suggestion.dart';
import 'package:gardnx_app/features/layout_planner/presentation/providers/recommendation_provider.dart';
import 'package:gardnx_app/features/layout_planner/presentation/screens/layout_editor_screen.dart';
import 'package:gardnx_app/features/manual_input/domain/models/manual_bed.dart';

class RecommendationScreen extends ConsumerWidget {
  final ManualBed bed;
  final String gardenId;
  final String season;
  final String region;

  const RecommendationScreen({
    super.key,
    required this.bed,
    required this.gardenId,
    required this.season,
    required this.region,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendationsAsync = ref.watch(recommendationsProvider);
    final selectedPlants = ref.watch(selectedPlantsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Recommendations'),
        actions: [
          if (selectedPlants.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Badge(
                  label: Text('${selectedPlants.length}'),
                  child: const Icon(Icons.local_florist),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Bed info card
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.grid_view,
                        color: colorScheme.primary, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bed.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          '${bed.widthCm}cm x ${bed.heightCm}cm  |  ${bed.sunExposureLabel}  |  ${bed.soilTypeLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Season: ${season.replaceAll('_', ' ')}  |  Region: ${region.toUpperCase()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Engine selector
          _EngineSelector(bed: bed, gardenId: gardenId, season: season, region: region),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  'Recommended Plants',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (recommendationsAsync.hasValue &&
                    (recommendationsAsync.value?.isNotEmpty ?? false))
                  TextButton(
                    onPressed: () {
                      final allIds = recommendationsAsync.value!
                          .map((r) => r.plantId)
                          .toList();
                      ref
                          .read(selectedPlantsProvider.notifier)
                          .selectAll(allIds);
                    },
                    child: const Text('Select All'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: recommendationsAsync.when(
              data: (suggestions) {
                if (suggestions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off,
                            size: 64,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(
                          'No recommendations available',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting bed settings or check back later',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = suggestions[index];
                    final isSelected =
                        selectedPlants.contains(suggestion.plantId);
                    return _SuggestionCard(
                      suggestion: suggestion,
                      isSelected: isSelected,
                      onToggle: () => ref
                          .read(selectedPlantsProvider.notifier)
                          .toggle(suggestion.plantId),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text('Failed to load recommendations'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(recommendationsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: selectedPlants.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LayoutEditorScreen(
                      bed: bed,
                      gardenId: gardenId,
                      season: season,
                      region: region,
                      selectedPlantIds: selectedPlants.toList(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.auto_fix_high),
              label:
                  Text('Generate Layout (${selectedPlants.length})'),
            )
          : null,
    );
  }
}

class _EngineSelector extends ConsumerWidget {
  final ManualBed bed;
  final String gardenId;
  final String season;
  final String region;

  const _EngineSelector({
    required this.bed,
    required this.gardenId,
    required this.season,
    required this.region,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineStatusAsync = ref.watch(engineStatusProvider);
    final preferredEngine = ref.watch(enginePreferenceProvider);
    final engineUsed = ref.watch(engineUsedProvider);
    final engineRequested = ref.watch(engineRequestedProvider);
    final fallbackReason = ref.watch(fallbackReasonProvider);
    final recommendationsAsync = ref.watch(recommendationsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Fixed list: Auto first, then each specific engine.
    const engines = [
      (null, 'Auto (best available)', Icons.auto_awesome_outlined),
      ('gemini', 'Gemini AI', Icons.auto_awesome),
      ('ollama', 'Ollama (Local)', Icons.computer),
      ('rules', 'Rule-based', Icons.rule),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_suggest, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text('AI Engine', style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary, fontWeight: FontWeight.bold,
                )),
                const Spacer(),
                // Show what was requested vs what was actually used
                if (engineRequested != null && engineRequested != preferredEngine)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      label: Text('Requested: $engineRequested',
                          style: const TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                if (engineUsed != null)
                  Chip(
                    label: Text('Using: $engineUsed',
                        style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: engineUsed == engineRequested || engineRequested == null
                        ? colorScheme.primaryContainer
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                // Loading spinner when fetching new recommendations
                if (recommendationsAsync.isLoading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            if (fallbackReason != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Fell back: $fallbackReason',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            engineStatusAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Could not check engine status',
                  style: TextStyle(fontSize: 12)),
              data: (statuses) => Column(
                children: engines.map((e) {
                  final key = e.$1;       // null = auto
                  final label = e.$2;
                  final icon = e.$3;

                  final status = key != null ? statuses[key] : null;
                  // Auto is always available; specific engines check their status.
                  final available = key == null ? true : (status?.available ?? false);
                  final reason = key == null
                      ? 'Let the backend pick the best available engine'
                      : (status?.reason ?? '');

                  // Highlighted when: key matches preference, or (auto + no preference set)
                  final isSelected = preferredEngine == key;

                  return InkWell(
                    onTap: available
                        ? () {
                            ref.read(enginePreferenceProvider.notifier).state = key;
                            ref.invalidate(recommendationsProvider);
                          }
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$label unavailable: $reason'),
                                duration: const Duration(seconds: 4),
                                action: SnackBarAction(
                                  label: 'OK',
                                  onPressed: () {},
                                ),
                              ),
                            );
                          },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(icon,
                              size: 18,
                              color: available
                                  ? (isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface)
                                  : colorScheme.onSurface
                                      .withValues(alpha: 0.3)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: available
                                          ? (isSelected
                                              ? colorScheme.primary
                                              : null)
                                          : colorScheme.onSurface
                                              .withValues(alpha: 0.4),
                                    )),
                                Text(reason,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: available
                                          ? colorScheme.onSurfaceVariant
                                          : colorScheme.error
                                              .withValues(alpha: 0.7),
                                    )),
                              ],
                            ),
                          ),
                          if (available)
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                            )
                          else
                            Icon(Icons.block,
                                size: 16,
                                color:
                                    colorScheme.error.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final LayoutSuggestion suggestion;
  final bool isSelected;
  final VoidCallback onToggle;

  const _SuggestionCard({
    required this.suggestion,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final score = suggestion.suitabilityScore;

    Color scoreColor;
    if (score >= 0.75) {
      scoreColor = Colors.green;
    } else if (score >= 0.5) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = colorScheme.error;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      suggestion.plantName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggle(),
                    shape: const CircleBorder(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Score bar
              Row(
                children: [
                  Text(
                    'Suitability: ${(score * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: scoreColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: score,
                        backgroundColor:
                            colorScheme.surfaceContainerHighest,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(scoreColor),
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Reasons
              ...suggestion.reasons.map((reason) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check, size: 12, color: scoreColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(reason,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  )),
              if (suggestion.companionNames.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: suggestion.companionNames
                      .map((name) => Chip(
                            label: Text(name),
                            avatar: const Icon(Icons.favorite,
                                size: 12, color: Colors.green),
                            backgroundColor:
                                Colors.green.withValues(alpha: 0.1),
                            visualDensity: VisualDensity.compact,
                            labelStyle: const TextStyle(fontSize: 11),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Max ${suggestion.maxCount} plant(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
