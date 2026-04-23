import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/models/garden_zone.dart';

/// Computes the rect that BoxFit.contain places the image in within [viewport].
Rect _containedImageRect(Size imageSize, Size viewport) {
  if (imageSize.isEmpty || viewport.isEmpty) {
    return Rect.fromLTWH(0, 0, viewport.width, viewport.height);
  }
  final imageAspect = imageSize.width / imageSize.height;
  final viewportAspect = viewport.width / viewport.height;

  if (imageAspect > viewportAspect) {
    // Letterbox: bars on top and bottom.
    final displayedHeight = viewport.width / imageAspect;
    final top = (viewport.height - displayedHeight) / 2;
    return Rect.fromLTWH(0, top, viewport.width, displayedHeight);
  } else {
    // Pillarbox: bars on left and right.
    final displayedWidth = viewport.height * imageAspect;
    final left = (viewport.width - displayedWidth) / 2;
    return Rect.fromLTWH(left, 0, displayedWidth, viewport.height);
  }
}

/// Renders a semi-transparent overlay of detected garden zones on top of
/// a photo.
///
/// Polygon coordinates are normalised (0–1) relative to the image.  The
/// overlay resolves the image's intrinsic size so it can map those
/// coordinates onto the correct sub-rect that BoxFit.contain uses, instead
/// of stretching them over the whole widget (which includes the letterbox
/// bars and produces a misaligned result).
class SegmentationOverlay extends StatefulWidget {
  final List<GardenZone> zones;
  final Set<String> selectedZoneIds;
  final void Function(String zoneId) onZoneTap;

  /// Local file path or network URL of the photo being displayed.
  /// Required so the overlay can resolve the image's intrinsic dimensions.
  final String? photoPath;

  const SegmentationOverlay({
    super.key,
    required this.zones,
    required this.selectedZoneIds,
    required this.onZoneTap,
    this.photoPath,
  });

  @override
  State<SegmentationOverlay> createState() => _SegmentationOverlayState();
}

class _SegmentationOverlayState extends State<SegmentationOverlay> {
  Size _imageSize = Size.zero;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant SegmentationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoPath != widget.photoPath) {
      _disposeStream();
      setState(() => _imageSize = Size.zero);
      _resolveImageSize();
    }
  }

  @override
  void dispose() {
    _disposeStream();
    super.dispose();
  }

  void _disposeStream() {
    if (_imageStream != null && _listener != null) {
      _imageStream!.removeListener(_listener!);
    }
    _imageStream = null;
    _listener = null;
  }

  void _resolveImageSize() {
    final path = widget.photoPath;
    if (path == null || path.isEmpty) return;

    final ImageProvider provider = path.startsWith('http')
        ? NetworkImage(path)
        : FileImage(File(path)) as ImageProvider;

    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
      stream.removeListener(listener);
      if (identical(_imageStream, stream)) {
        _imageStream = null;
        _listener = null;
      }
    });
    _imageStream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final imageRect = _containedImageRect(_imageSize, viewport);

        return GestureDetector(
          onTapDown: (details) =>
              _handleTap(details.localPosition, imageRect),
          child: CustomPaint(
            painter: _SegmentationPainter(
              zones: widget.zones,
              selectedZoneIds: widget.selectedZoneIds,
              imageRect: imageRect,
            ),
            size: viewport,
          ),
        );
      },
    );
  }

  void _handleTap(Offset tapPosition, Rect imageRect) {
    // Check zones in reverse order (top-most drawn last).
    for (int i = widget.zones.length - 1; i >= 0; i--) {
      final zone = widget.zones[i];
      if (zone.polygon.isEmpty) continue;

      final path = Path();
      final pts = zone.polygon
          .map((p) => Offset(
                imageRect.left + p.dx * imageRect.width,
                imageRect.top + p.dy * imageRect.height,
              ))
          .toList();

      path.moveTo(pts.first.dx, pts.first.dy);
      for (int j = 1; j < pts.length; j++) {
        path.lineTo(pts[j].dx, pts[j].dy);
      }
      path.close();

      if (path.contains(tapPosition)) {
        widget.onZoneTap(zone.zoneId);
        return;
      }
    }
  }
}

class _SegmentationPainter extends CustomPainter {
  final List<GardenZone> zones;
  final Set<String> selectedZoneIds;
  final Rect imageRect;

  _SegmentationPainter({
    required this.zones,
    required this.selectedZoneIds,
    required this.imageRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final zone in zones) {
      if (zone.polygon.isEmpty) continue;

      final isSelected = selectedZoneIds.contains(zone.zoneId);

      // Map normalised (0–1) coords onto the actual displayed image rect.
      final pts = zone.polygon
          .map((p) => Offset(
                imageRect.left + p.dx * imageRect.width,
                imageRect.top + p.dy * imageRect.height,
              ))
          .toList();

      final path = Path();
      path.moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();

      // Fill
      canvas.drawPath(
        path,
        Paint()
          ..color = zone.color.withValues(alpha: isSelected ? 0.45 : 0.25)
          ..style = PaintingStyle.fill,
      );

      // Stroke
      canvas.drawPath(
        path,
        Paint()
          ..color =
              isSelected ? zone.color : zone.color.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3.0 : 1.5,
      );

      // Label on selected zones
      if (isSelected) {
        _drawLabel(canvas, zone.displayLabel, _centroid(pts));
      }
    }
  }

  Offset _centroid(List<Offset> pts) {
    double cx = 0, cy = 0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    return Offset(cx / pts.length, cy / pts.length);
  }

  void _drawLabel(Canvas canvas, String label, Offset position) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: Colors.white,
        shadows: [
          Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 3),
        ],
      ))
      ..addText(label);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 100));

    final bgRect = Rect.fromCenter(
      center: position,
      width: paragraph.longestLine + 12,
      height: paragraph.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.fill,
    );

    canvas.drawParagraph(
      paragraph,
      Offset(
        position.dx - paragraph.longestLine / 2,
        position.dy - paragraph.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _SegmentationPainter old) =>
      old.zones != zones ||
      old.selectedZoneIds != selectedZoneIds ||
      old.imageRect != imageRect;
}
