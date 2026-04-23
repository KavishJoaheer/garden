import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme/app_colors.dart';

/// Screen where the user draws a rectangle on the garden photo to select
/// an area of interest before analysis.
class AreaSelectionScreen extends ConsumerStatefulWidget {
  /// Path to the photo (local file or network URL).
  final String? photoPath;

  /// Callback invoked when the user confirms a selection rect (normalised 0-1).
  final void Function(Rect normalizedRect)? onAreaSelected;

  const AreaSelectionScreen({
    super.key,
    this.photoPath,
    this.onAreaSelected,
  });

  static const routeName = '/garden/select-area';

  @override
  ConsumerState<AreaSelectionScreen> createState() =>
      _AreaSelectionScreenState();
}

class _AreaSelectionScreenState extends ConsumerState<AreaSelectionScreen> {
  Offset? _startPoint;
  Offset? _endPoint;
  bool _isDragging = false;
  Size _viewportSize = Size.zero;
  Size _sourceImageSize = Size.zero;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  Rect? get _selectionRect {
    if (_startPoint == null || _endPoint == null) return null;

    final left = math.min(_startPoint!.dx, _endPoint!.dx);
    final top = math.min(_startPoint!.dy, _endPoint!.dy);
    final right = math.max(_startPoint!.dx, _endPoint!.dx);
    final bottom = math.max(_startPoint!.dy, _endPoint!.dy);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Converts the drawn rect to normalised coordinates (0-1).
  Rect? get _normalizedRect {
    final rect = _selectionRect;
    final imageRect = _displayedImageRect;
    if (rect == null || imageRect == null) return null;

    return Rect.fromLTRB(
      ((rect.left - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
      ((rect.top - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
      ((rect.right - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
      ((rect.bottom - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
    );
  }

  Rect? get _displayedImageRect {
    if (_viewportSize == Size.zero) return null;
    if (_sourceImageSize == Size.zero) {
      return Rect.fromLTWH(0, 0, _viewportSize.width, _viewportSize.height);
    }

    final imageAspect = _sourceImageSize.width / _sourceImageSize.height;
    final viewportAspect = _viewportSize.width / _viewportSize.height;

    if (imageAspect > viewportAspect) {
      final displayedHeight = _viewportSize.width / imageAspect;
      final top = (_viewportSize.height - displayedHeight) / 2;
      return Rect.fromLTWH(0, top, _viewportSize.width, displayedHeight);
    }

    final displayedWidth = _viewportSize.height * imageAspect;
    final left = (_viewportSize.width - displayedWidth) / 2;
    return Rect.fromLTWH(left, 0, displayedWidth, _viewportSize.height);
  }

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant AreaSelectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoPath != widget.photoPath) {
      _disposeImageStream();
      _sourceImageSize = Size.zero;
      _resolveImageSize();
    }
  }

  @override
  void dispose() {
    _disposeImageStream();
    super.dispose();
  }

  void _disposeImageStream() {
    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  void _resolveImageSize() {
    final photoPath = widget.photoPath;
    if (photoPath == null || photoPath.isEmpty) return;

    final imageProvider = photoPath.startsWith('http')
        ? NetworkImage(photoPath)
        : FileImage(File(photoPath)) as ImageProvider;

    final stream = imageProvider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((imageInfo, _) {
      if (!mounted) return;
      setState(() {
        _sourceImageSize = Size(
          imageInfo.image.width.toDouble(),
          imageInfo.image.height.toDouble(),
        );
      });
      stream.removeListener(listener);
      if (identical(_imageStream, stream)) {
        _imageStream = null;
        _imageStreamListener = null;
      }
    });

    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  Offset _clampToImageBounds(Offset point) {
    final imageRect = _displayedImageRect;
    if (imageRect == null) return point;
    return Offset(
      point.dx.clamp(imageRect.left, imageRect.right),
      point.dy.clamp(imageRect.top, imageRect.bottom),
    );
  }

  void _handleConfirm() {
    final norm = _normalizedRect;
    if (norm == null || norm.width < 0.05 || norm.height < 0.05) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please draw a larger selection area.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    widget.onAreaSelected?.call(norm);
    Navigator.of(context).pop(norm);
  }

  void _handleReset() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Area'),
        actions: [
          if (_selectionRect != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset Selection',
              onPressed: _handleReset,
            ),
        ],
      ),
      body: Column(
        children: [
          // ----- Instruction text -----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.infoContainer,
            child: const Row(
              children: [
                Icon(Icons.touch_app, color: AppColors.info, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Draw a rectangle around the area you want to plan',
                    style: TextStyle(color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),

          // ----- Photo + selection overlay -----
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Gesture area (covers the full viewport)
                    GestureDetector(
                      onPanStart: (details) {
                        final localPoint =
                            _clampToImageBounds(details.localPosition);
                        setState(() {
                          _startPoint = localPoint;
                          _endPoint = localPoint;
                          _isDragging = true;
                        });
                      },
                      onPanUpdate: (details) {
                        if (_isDragging) {
                          setState(() {
                            _endPoint =
                                _clampToImageBounds(details.localPosition);
                          });
                        }
                      },
                      onPanEnd: (_) {
                        setState(() {
                          _isDragging = false;
                        });
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Background photo
                          _buildPhotoWidget(),

                          // Selection rect overlay
                          if (_selectionRect != null)
                            CustomPaint(
                              painter: _AreaSelectionPainter(
                                rect: _selectionRect!,
                                isDragging: _isDragging,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Bottom confirm/reset bar — rendered as overlay so the
                    // viewport (and therefore the displayed image rect) does
                    // not change when it appears, preventing selection drift.
                    if (_selectionRect != null && !_isDragging)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildBottomBar(),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoWidget() {
    if (widget.photoPath == null) {
      return Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 64),
        ),
      );
    }

    final path = widget.photoPath!;

    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.surfaceVariant,
          child: const Icon(Icons.broken_image, size: 64),
        ),
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.broken_image, size: 64),
      ),
    );
  }

  Widget _buildBottomBar() {
    final norm = _normalizedRect;
    final widthPct = norm != null ? (norm.width * 100).toStringAsFixed(0) : '0';
    final heightPct =
        norm != null ? (norm.height * 100).toStringAsFixed(0) : '0';

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Selected area: $widthPct% x $heightPct%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _handleReset,
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _handleConfirm,
                    child: const Text('Confirm Area'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the selection rectangle overlay with dimmed regions outside.
class _AreaSelectionPainter extends CustomPainter {
  final Rect rect;
  final bool isDragging;

  _AreaSelectionPainter({required this.rect, required this.isDragging});

  @override
  void paint(Canvas canvas, Size size) {
    // Dim the area outside the selection
    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    // Draw dimmed regions (four rectangles around the selection)
    // Top
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, rect.top),
      dimPaint,
    );
    // Bottom
    canvas.drawRect(
      Rect.fromLTRB(0, rect.bottom, size.width, size.height),
      dimPaint,
    );
    // Left
    canvas.drawRect(
      Rect.fromLTRB(0, rect.top, rect.left, rect.bottom),
      dimPaint,
    );
    // Right
    canvas.drawRect(
      Rect.fromLTRB(rect.right, rect.top, size.width, rect.bottom),
      dimPaint,
    );

    // Selection border
    final borderPaint = Paint()
      ..color = isDragging ? AppColors.primary : AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawRect(rect, borderPaint);

    // Corner handles
    const handleSize = 12.0;
    final handlePaint = Paint()
      ..color = isDragging ? AppColors.primary : AppColors.accent
      ..style = PaintingStyle.fill;

    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];

    for (final corner in corners) {
      canvas.drawCircle(corner, handleSize / 2, handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaSelectionPainter oldDelegate) {
    return oldDelegate.rect != rect || oldDelegate.isDragging != isDragging;
  }
}
