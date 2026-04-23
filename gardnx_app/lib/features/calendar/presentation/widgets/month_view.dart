import 'package:flutter/material.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';

class MonthView extends StatelessWidget {
  final Plant plant;
  final int currentMonth;

  const MonthView({
    super.key,
    required this.plant,
    required this.currentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plant.name,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: Row(
            children: List.generate(12, (index) {
              final month = index + 1;
              final isSow = plant.timing.sowMonths.contains(month);
              final isTransplant =
                  plant.timing.transplantMonths.contains(month);
              final isHarvest = plant.timing.harvestMonths.contains(month);
              final isCurrent = month == currentMonth;

              Color? cellColor;
              if (isSow && isTransplant) {
                cellColor = Colors.blue.withOpacity(0.7);
              } else if (isSow) {
                cellColor = Colors.green.withOpacity(0.7);
              } else if (isTransplant) {
                cellColor = Colors.blue.withOpacity(0.5);
              } else if (isHarvest) {
                cellColor = Colors.orange.withOpacity(0.7);
              }

              return Expanded(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                  decoration: BoxDecoration(
                    color: cellColor ?? colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: isCurrent
                        ? Border.all(color: colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      _shortMonth(month),
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: cellColor != null
                            ? Colors.white
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        // Legend row
        Wrap(
          spacing: 8,
          children: [
            _LegendDot(color: Colors.green, label: 'Sow'),
            _LegendDot(color: Colors.blue, label: 'Transplant'),
            _LegendDot(color: Colors.orange, label: 'Harvest'),
          ],
        ),
      ],
    );
  }

  String _shortMonth(int month) {
    const names = [
      '', 'J', 'F', 'M', 'A', 'M', 'J',
      'J', 'A', 'S', 'O', 'N', 'D'
    ];
    return names[month];
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 9)),
      ],
    );
  }
}

/// Widget that shows a 12-month bar chart for multiple plants.
class PlantCalendarChart extends StatelessWidget {
  final List<Plant> plants;

  const PlantCalendarChart({super.key, required this.plants});

  @override
  Widget build(BuildContext context) {
    final currentMonth = DateTime.now().month;

    if (plants.isEmpty) {
      return const Center(child: Text('No plants in this garden yet.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: plants.length,
      separatorBuilder: (_, __) => const Divider(height: 20),
      itemBuilder: (context, index) {
        return MonthView(
          plant: plants[index],
          currentMonth: currentMonth,
        );
      },
    );
  }
}
