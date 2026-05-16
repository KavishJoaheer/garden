import 'package:flutter/material.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';

class PlantCard extends StatelessWidget {
  final Plant plant;
  final VoidCallback? onTap;

  const PlantCard({super.key, required this.plant, this.onTap});

  Color _categoryColor(String category) {
    switch (category) {
      case 'vegetable':
        return Colors.green;
      case 'herb':
        return Colors.teal;
      case 'fruit':
        return Colors.orange;
      case 'flower':
        return Colors.pink;
      case 'ornamental':
        return Colors.indigo;
      case 'tree':
        return Colors.brown;
      case 'shrub':
        return Colors.deepPurple;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'vegetable':
        return Icons.eco;
      case 'herb':
        return Icons.spa;
      case 'fruit':
        return Icons.apple;
      case 'flower':
        return Icons.local_florist;
      case 'ornamental':
        return Icons.park;
      case 'tree':
        return Icons.nature;
      case 'shrub':
        return Icons.grass;
      default:
        return Icons.yard;
    }
  }

  IconData _difficultyIcon(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return Icons.sentiment_satisfied;
      case 'medium':
        return Icons.sentiment_neutral;
      case 'hard':
        return Icons.sentiment_dissatisfied;
      default:
        return Icons.sentiment_satisfied;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final categoryColor = _categoryColor(plant.category);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image or placeholder
            AspectRatio(
              aspectRatio: 4 / 3,
              child: plant.imageUrl != null
                  ? Image.network(
                      plant.imageUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return _PlaceholderImage(plant: plant, isLoading: true);
                      },
                      errorBuilder: (_, __, ___) =>
                          _PlaceholderImage(plant: plant),
                    )
                  : _PlaceholderImage(plant: plant),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plant.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      plant.scientificName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: categoryColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _categoryIcon(plant.category),
                                size: 10,
                                color: categoryColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                plant.category,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: categoryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _difficultyIcon(plant.difficultyLevel),
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Suitability bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: plant.suitabilityScore,
                        backgroundColor:
                            colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          plant.suitabilityScore > 0.7
                              ? Colors.green
                              : plant.suitabilityScore > 0.4
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  final Plant plant;
  final bool isLoading;

  const _PlaceholderImage({
    required this.plant,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.primaryContainer.withOpacity(0.4),
      child: Center(
        child: isLoading
            ? SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary.withOpacity(0.7),
                ),
              )
            : Icon(
                Icons.local_florist,
                size: 48,
                color: colorScheme.primary.withOpacity(0.5),
              ),
      ),
    );
  }
}
