import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';
import 'package:gardnx_app/features/plant_database/domain/models/companion_rule.dart';
import 'package:gardnx_app/features/plant_database/presentation/providers/plant_provider.dart';

class PlantDetailScreen extends ConsumerWidget {
  final String plantId;

  /// When provided, skips the Firestore lookup entirely (used for Perenual
  /// plants that are not stored in Firestore).
  final Plant? preloadedPlant;

  const PlantDetailScreen({
    super.key,
    required this.plantId,
    this.preloadedPlant,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If the caller already has the Plant object (e.g. from a global search),
    // use it directly without hitting Firestore.
    if (preloadedPlant != null) {
      return _PlantDetailBody(plant: preloadedPlant!);
    }

    final plantAsync = ref.watch(plantByIdProvider(plantId));

    return plantAsync.when(
      data: (plant) {
        if (plant == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Plant not found.')),
          );
        }
        return _PlantDetailBody(plant: plant);
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _PlantDetailBody extends ConsumerStatefulWidget {
  final Plant plant;

  const _PlantDetailBody({required this.plant});

  @override
  ConsumerState<_PlantDetailBody> createState() => _PlantDetailBodyState();
}

class _PlantDetailBodyState extends ConsumerState<_PlantDetailBody> {
  bool _isSaving = false;
  bool _saved = false;

  String _monthName(int month) {
    const names = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[month];
  }

  String _monthListLabel(List<int> months) {
    if (months.isEmpty) return 'N/A';
    return months.map(_monthName).join(', ');
  }

  Future<void> _saveToCollection() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(addPlantProvider)(widget.plant);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saved = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.plant.name} added to your collection!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final companionRulesAsync =
        ref.watch(companionRulesForPlantProvider(plant.id));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero image app bar
          SliverAppBar.large(
            expandedHeight: 240,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(plant.name),
              background: plant.imageUrl != null
                  ? Image.network(
                      plant.imageUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return _PlantDetailPlaceholder(
                          icon: Icons.local_florist,
                        );
                      },
                      errorBuilder: (_, __, ___) =>
                          const _PlantDetailPlaceholder(
                        icon: Icons.local_florist,
                      ),
                    )
                  : Container(
                      color: colorScheme.primaryContainer,
                      child: Icon(Icons.local_florist,
                          size: 80,
                          color: colorScheme.primary.withOpacity(0.5)),
                    ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                // Scientific name & category
                Row(
                  children: [
                    Text(
                      plant.scientificName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    _CategoryChip(category: plant.category),
                  ],
                ),
                const SizedBox(height: 12),

                // Description
                Text(plant.description, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 20),

                // Suitability score
                _SectionCard(
                  title: 'Mauritius Suitability',
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(plant.suitabilityScore * 100).round()}%',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: plant.suitabilityScore > 0.7
                                  ? Colors.green
                                  : plant.suitabilityScore > 0.4
                                      ? Colors.orange
                                      : colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _DifficultyBadge(level: plant.difficultyLevel),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: plant.suitabilityScore,
                          minHeight: 10,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            plant.suitabilityScore > 0.7
                                ? Colors.green
                                : plant.suitabilityScore > 0.4
                                    ? Colors.orange
                                    : colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Growing conditions
                _SectionCard(
                  title: 'Growing Conditions',
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.thermostat,
                        label: 'Temperature',
                        value:
                            '${plant.conditions.minTempC.toInt()}\u2013${plant.conditions.maxTempC.toInt()}\u00b0C',
                      ),
                      _InfoRow(
                        icon: Icons.wb_sunny,
                        label: 'Sun',
                        value: plant.conditions.sunRequirement
                            .replaceAll('_', ' ')
                            .toCapitalized(),
                      ),
                      _InfoRow(
                        icon: Icons.water_drop,
                        label: 'Water',
                        value: plant.conditions.waterNeeds.toCapitalized(),
                      ),
                      _InfoRow(
                        icon: Icons.water,
                        label: 'Humidity',
                        value:
                            '${plant.conditions.minHumidity.toInt()}\u2013${plant.conditions.maxHumidity.toInt()}%',
                      ),
                      _InfoRow(
                        icon: Icons.landscape,
                        label: 'Soil',
                        value: plant.conditions.suitableSoils
                            .map((s) => s.toCapitalized())
                            .join(', '),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Spacing & layout
                _SectionCard(
                  title: 'Spacing & Layout',
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.swap_horiz,
                        label: 'Row Spacing',
                        value: '${plant.spacing.rowSpacingCm} cm',
                      ),
                      _InfoRow(
                        icon: Icons.height,
                        label: 'Plant Spacing',
                        value: '${plant.spacing.plantSpacingCm} cm',
                      ),
                      _InfoRow(
                        icon: Icons.grid_4x4,
                        label: 'Grid Cells',
                        value:
                            '${plant.spacing.gridCellsRequired} cell(s)',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Timing
                _SectionCard(
                  title: 'Planting Calendar',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (plant.timing.sowMonths.isNotEmpty)
                        _InfoRow(
                          icon: Icons.grass,
                          label: 'Sow',
                          value: _monthListLabel(plant.timing.sowMonths),
                        ),
                      if (plant.timing.transplantMonths.isNotEmpty)
                        _InfoRow(
                          icon: Icons.swap_horiz,
                          label: 'Transplant',
                          value:
                              _monthListLabel(plant.timing.transplantMonths),
                        ),
                      if (plant.timing.harvestMonths.isNotEmpty)
                        _InfoRow(
                          icon: Icons.cut,
                          label: 'Harvest',
                          value: _monthListLabel(plant.timing.harvestMonths),
                        ),
                      if (plant.timing.sowMonths.isEmpty &&
                          plant.timing.transplantMonths.isEmpty &&
                          plant.timing.harvestMonths.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Planting schedule not available for this plant.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      _InfoRow(
                        icon: Icons.timer,
                        label: 'Days to Maturity',
                        value: '${plant.timing.daysToMaturity} days',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Companion rules
                companionRulesAsync.when(
                  data: (rules) {
                    if (rules.isEmpty) return const SizedBox.shrink();
                    final companions = rules
                        .where((r) => r.type == CompanionType.companion)
                        .toList();
                    final incompatibles = rules
                        .where((r) => r.type == CompanionType.incompatible)
                        .toList();
                    return _SectionCard(
                      title: 'Companion Planting',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (companions.isNotEmpty) ...[
                            const _CompanionHeader(
                                label: 'Good Companions',
                                color: Colors.green),
                            ...companions.map((r) => Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8, bottom: 4),
                                  child: Text('\u2022 ${r.reason}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                )),
                          ],
                          if (incompatibles.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const _CompanionHeader(
                                label: 'Avoid Nearby', color: Colors.red),
                            ...incompatibles.map((r) => Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8, bottom: 4),
                                  child: Text('\u2022 ${r.reason}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                )),
                          ],
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                // Save to collection button — only for Perenual plants
                if (plant.id.startsWith('perenual_')) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_isSaving || _saved)
                          ? null
                          : _saveToCollection,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(_saved
                              ? Icons.check_circle_outline
                              : Icons.add_circle_outline),
                      label: Text(_saved
                          ? 'Saved to Collection'
                          : 'Save to My Collection'),
                    ),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlantDetailPlaceholder extends StatelessWidget {
  final IconData icon;

  const _PlantDetailPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.primaryContainer,
      child: Icon(
        icon,
        size: 80,
        color: colorScheme.primary.withOpacity(0.5),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              )),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;

  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(category.toCapitalized()),
      backgroundColor: colorScheme.secondaryContainer,
      labelStyle: TextStyle(
          color: colorScheme.onSecondaryContainer, fontSize: 12),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DifficultyBadge extends StatelessWidget {
  final String level;

  const _DifficultyBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (level) {
      case 'easy':
        color = Colors.green;
        break;
      case 'medium':
        color = Colors.orange;
        break;
      default:
        color = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(level.toCapitalized(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _CompanionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _CompanionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

extension _StringExt on String {
  String toCapitalized() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
