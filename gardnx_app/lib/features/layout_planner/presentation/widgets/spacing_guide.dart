import 'package:flutter/material.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/garden_layout.dart';

class SpacingGuide extends StatelessWidget {
  final GardenLayout layout;
  final int? maxPlantCount;

  const SpacingGuide({
    super.key,
    required this.layout,
    this.maxPlantCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final totalCells = layout.totalCells;
    final occupiedCells = layout.occupiedCells;
    final utilizationPercent = totalCells > 0
        ? (occupiedCells / totalCells * 100).round()
        : 0;

    Color utilizationColor;
    if (utilizationPercent < 40) {
      utilizationColor = Colors.blue;
    } else if (utilizationPercent < 80) {
      utilizationColor = Colors.green;
    } else if (utilizationPercent < 95) {
      utilizationColor = Colors.orange;
    } else {
      utilizationColor = Colors.red;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bed Utilization',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: occupiedCells / totalCells.clamp(1, totalCells),
                      minHeight: 10,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          utilizationColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$utilizationPercent%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: utilizationColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatChip(
                  label: 'Used',
                  value: '$occupiedCells cells',
                  color: utilizationColor,
                ),
                _StatChip(
                  label: 'Free',
                  value: '${totalCells - occupiedCells} cells',
                  color: colorScheme.primary,
                ),
                _StatChip(
                  label: 'Total',
                  value: '$totalCells cells',
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (maxPlantCount != null) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Max plants for this bed: $maxPlantCount',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}
