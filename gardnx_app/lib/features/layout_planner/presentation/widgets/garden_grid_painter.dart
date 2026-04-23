import 'package:flutter/material.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/garden_layout.dart';
import 'package:gardnx_app/features/layout_planner/domain/models/plant_placement.dart';

// Plant type to color mapping
class PlantColorMap {
  static const List<Color> _palette = [
    Color(0xFF66BB6A), // green
    Color(0xFF42A5F5), // blue
    Color(0xFFFF7043), // orange
    Color(0xFFAB47BC), // purple
    Color(0xFF26C6DA), // cyan
    Color(0xFFEC407A), // pink
    Color(0xFF8D6E63), // brown
    Color(0xFFFFCA28), // amber
  ];

  static Color forPlant(String plantId, int index) {
    return _palette[index % _palette.length];
  }
}

// Plant emoji icons — looked up by lowercase plant name substring.
class PlantEmojiMap {
  static const Map<String, String> _byName = {
    'tomato': '🍅',
    'lettuce': '🥬',
    'carrot': '🥕',
    'pepper': '🌶',
    'capsicum': '🌶',
    'chili': '🌶',
    'chilli': '🌶',
    'cucumber': '🥒',
    'eggplant': '🍆',
    'aubergine': '🍆',
    'brinjal': '🍆',
    'spinach': '🥬',
    'cabbage': '🥦',
    'broccoli': '🥦',
    'cauliflower': '🥦',
    'bean': '🫘',
    'pea': '🫛',
    'corn': '🌽',
    'maize': '🌽',
    'onion': '🧅',
    'garlic': '🧄',
    'potato': '🥔',
    'sweet potato': '🍠',
    'pumpkin': '🎃',
    'squash': '🥒',
    'zucchini': '🥒',
    'courgette': '🥒',
    'radish': '🌱',
    'beetroot': '🌱',
    'kale': '🥬',
    'leek': '🧅',
    'celery': '🌿',
    'mint': '🌿',
    'basil': '🌿',
    'parsley': '🌿',
    'coriander': '🌿',
    'cilantro': '🌿',
    'thyme': '🌿',
    'rosemary': '🌿',
    'chive': '🌿',
    'dill': '🌿',
    'sage': '🌿',
    'lemongrass': '🌿',
    'strawberry': '🍓',
    'mango': '🥭',
    'banana': '🍌',
    'papaya': '🍈',
    'pineapple': '🍍',
    'lemon': '🍋',
    'lime': '🍋',
    'orange': '🍊',
    'watermelon': '🍉',
    'melon': '🍈',
    'grape': '🍇',
    'cherry': '🍒',
    'apple': '🍎',
    'pear': '🍐',
    'guava': '🍈',
    'sunflower': '🌻',
    'rose': '🌹',
    'lavender': '💜',
    'marigold': '🌼',
    'hibiscus': '🌺',
    'jasmine': '🌸',
  };

  static const Map<String, String> _byCategory = {
    'vegetable': '🥦',
    'herb': '🌿',
    'fruit': '🍓',
    'flower': '🌸',
  };

  /// Returns the best emoji for [plantName], falling back to [category].
  static String get(String plantName, [String category = '']) {
    final lower = plantName.toLowerCase();
    for (final entry in _byName.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return _byCategory[category.toLowerCase()] ?? '🌱';
  }
}

class GardenGridWidget extends StatefulWidget {
  final GardenLayout layout;
  final String? selectedPlacementId;
  final Set<String>? companionPlantIds;
  final Set<String>? incompatiblePlantIds;
  final void Function(int row, int col)? onCellTap;
  final void Function(String placementId)? onPlacementTap;

  const GardenGridWidget({
    super.key,
    required this.layout,
    this.selectedPlacementId,
    this.companionPlantIds,
    this.incompatiblePlantIds,
    this.onCellTap,
    this.onPlacementTap,
  });

  @override
  State<GardenGridWidget> createState() => _GardenGridWidgetState();
}

class _GardenGridWidgetState extends State<GardenGridWidget> {
  late Map<String, int> _plantColorIndex;

  @override
  void initState() {
    super.initState();
    _buildColorMap();
  }

  @override
  void didUpdateWidget(GardenGridWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout.placements != widget.layout.placements) {
      _buildColorMap();
    }
  }

  void _buildColorMap() {
    _plantColorIndex = {};
    int idx = 0;
    for (final p in widget.layout.placements) {
      if (!_plantColorIndex.containsKey(p.plantId)) {
        _plantColorIndex[p.plantId] = idx++;
      }
    }
  }

  void _handleTap(Offset localPosition, double cellSize) {
    final col = (localPosition.dx / cellSize).floor();
    final row = (localPosition.dy / cellSize).floor();

    if (row < 0 ||
        row >= widget.layout.gridRows ||
        col < 0 ||
        col >= widget.layout.gridCols) {
      return;
    }

    // Check if a placement was tapped
    for (final p in widget.layout.placements) {
      if (p.occupies(row, col)) {
        widget.onPlacementTap?.call(p.id);
        return;
      }
    }
    widget.onCellTap?.call(row, col);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final cellByWidth = maxWidth / widget.layout.gridCols;
        final cellByHeight = maxHeight / widget.layout.gridRows;
        final cellSize = cellByWidth < cellByHeight ? cellByWidth : cellByHeight;

        final gridWidth = cellSize * widget.layout.gridCols;
        final gridHeight = cellSize * widget.layout.gridRows;

        return Center(
          child: GestureDetector(
            onTapUp: (details) => _handleTap(details.localPosition, cellSize),
            child: SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: CustomPaint(
                painter: GardenGridPainter(
                  layout: widget.layout,
                  cellSize: cellSize,
                  plantColorIndex: _plantColorIndex,
                  selectedPlacementId: widget.selectedPlacementId,
                  companionPlantIds: widget.companionPlantIds ?? {},
                  incompatiblePlantIds:
                      widget.incompatiblePlantIds ?? {},
                ),
                size: Size(gridWidth, gridHeight),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GardenGridPainter extends CustomPainter {
  final GardenLayout layout;
  final double cellSize;
  final Map<String, int> plantColorIndex;
  final String? selectedPlacementId;
  final Set<String> companionPlantIds;
  final Set<String> incompatiblePlantIds;

  GardenGridPainter({
    required this.layout,
    required this.cellSize,
    required this.plantColorIndex,
    this.selectedPlacementId,
    required this.companionPlantIds,
    required this.incompatiblePlantIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw empty cells
    _drawEmptyCells(canvas);

    // 2. Draw plant cells
    for (final placement in layout.placements) {
      _drawPlacement(canvas, placement);
    }

    // 3. Draw grid lines on top
    _drawGridLines(canvas, size);
  }

  void _drawEmptyCells(Canvas canvas) {
    final emptyPaint = Paint()..color = const Color(0xFFF5F0E8);
    for (int r = 0; r < layout.gridRows; r++) {
      for (int c = 0; c < layout.gridCols; c++) {
        final rect = Rect.fromLTWH(
            c * cellSize, r * cellSize, cellSize, cellSize);
        canvas.drawRect(rect, emptyPaint);
      }
    }
  }

  void _drawGridLines(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    for (int c = 0; c <= layout.gridCols; c++) {
      canvas.drawLine(
        Offset(c * cellSize, 0),
        Offset(c * cellSize, size.height),
        paint,
      );
    }
    for (int r = 0; r <= layout.gridRows; r++) {
      canvas.drawLine(
        Offset(0, r * cellSize),
        Offset(size.width, r * cellSize),
        paint,
      );
    }
  }

  void _drawPlacement(Canvas canvas, PlantPlacement placement) {
    final colorIdx = plantColorIndex[placement.plantId] ?? 0;
    final baseColor = PlantColorMap.forPlant(placement.plantId, colorIdx);
    final isSelected = placement.id == selectedPlacementId;
    final isCompanion = companionPlantIds.contains(placement.plantId);
    final isIncompatible = incompatiblePlantIds.contains(placement.plantId);

    final rect = Rect.fromLTWH(
      placement.startCol * cellSize,
      placement.startRow * cellSize,
      placement.colSpan * cellSize,
      placement.rowSpan * cellSize,
    );

    // Fill
    canvas.drawRect(
      rect,
      Paint()
        ..color = baseColor.withValues(alpha: isSelected ? 0.85 : 0.65),
    );

    // Companion border (green glow)
    if (isCompanion) {
      canvas.drawRect(
        rect.deflate(1.5),
        Paint()
          ..color = Colors.green.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Incompatible border (red glow)
    if (isIncompatible) {
      canvas.drawRect(
        rect.deflate(1.5),
        Paint()
          ..color = Colors.red.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Selection border
    if (isSelected) {
      canvas.drawRect(
        rect.deflate(1.25),
        Paint()
          ..color = Colors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Emoji icon (large cells) or initials fallback (tiny cells)
    final emoji = PlantEmojiMap.get(placement.plantName);
    final emojiFontSize = (cellSize * 0.55).clamp(10.0, 26.0);

    if (cellSize >= 18) {
      // Draw emoji
      final emojiPainter = TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(fontSize: emojiFontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width);

      emojiPainter.paint(
        canvas,
        rect.center -
            Offset(emojiPainter.width / 2, emojiPainter.height / 2),
      );
    } else {
      // Cells are too small for emoji — fall back to initials
      final initials = _getInitials(placement.plantName);
      final tp = TextPainter(
        text: TextSpan(
          text: initials,
          style: TextStyle(
            color: _contrastColor(baseColor),
            fontSize: (cellSize * 0.35).clamp(6.0, 14.0),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width);

      tp.paint(
        canvas,
        rect.center - Offset(tp.width / 2, tp.height / 2),
      );
    }
  }

  String _getInitials(String name) {
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  Color _contrastColor(Color bg) {
    return bg.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;
  }

  @override
  bool shouldRepaint(GardenGridPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.cellSize != cellSize ||
      oldDelegate.selectedPlacementId != selectedPlacementId ||
      oldDelegate.companionPlantIds != companionPlantIds ||
      oldDelegate.incompatiblePlantIds != incompatiblePlantIds;
}
