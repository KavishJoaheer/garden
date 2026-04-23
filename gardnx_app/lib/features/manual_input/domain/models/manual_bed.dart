import 'dart:ui';

/// Represents a manually drawn garden bed.
///
/// In Firestore the document ID (`doc.id`) is the source of truth for [id].
/// Older documents stored a separate embedded `id` field; it is ignored on
/// read and never written on save.
class ManualBed {
  final String id;
  final String name;
  final double widthCm;
  final double heightCm;
  final String sunExposure; // 'full_sun', 'partial_shade', 'full_shade'
  final String soilType; // 'clay', 'loam', 'sandy', 'silt', 'peat', 'chalk'
  final Rect rect; // Position and size on the canvas (in logical pixels)
  final Color color;

  const ManualBed({
    required this.id,
    required this.name,
    this.widthCm = 100,
    this.heightCm = 100,
    this.sunExposure = 'full_sun',
    this.soilType = 'loam',
    this.rect = Rect.zero,
    this.color = const Color(0xFF8D6E63),
  });

  /// Creates from a Firestore document. The [docId] is authoritative; any
  /// `id` value embedded in [map] is ignored.
  factory ManualBed.fromFirestore(
    String docId,
    Map<String, dynamic> map,
  ) {
    return ManualBed(
      id: docId,
      name: map['name'] as String? ?? 'Untitled Bed',
      widthCm: (map['widthCm'] as num?)?.toDouble() ?? 100,
      heightCm: (map['heightCm'] as num?)?.toDouble() ?? 100,
      sunExposure: map['sunExposure'] as String? ?? 'full_sun',
      soilType: map['soilType'] as String? ?? 'loam',
      rect: Rect.fromLTWH(
        (map['rectLeft'] as num?)?.toDouble() ?? 0,
        (map['rectTop'] as num?)?.toDouble() ?? 0,
        (map['rectWidth'] as num?)?.toDouble() ?? 100,
        (map['rectHeight'] as num?)?.toDouble() ?? 100,
      ),
      color: Color((map['color'] as int?) ?? 0xFF8D6E63),
    );
  }

  /// Converts to a Firestore-compatible map.
  ///
  /// Deliberately omits `id` — callers rely on the Firestore document ID.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'widthCm': widthCm,
      'heightCm': heightCm,
      'sunExposure': sunExposure,
      'soilType': soilType,
      'rectLeft': rect.left,
      'rectTop': rect.top,
      'rectWidth': rect.width,
      'rectHeight': rect.height,
      'color': color.toARGB32(),
    };
  }

  /// Returns a user-friendly label for the sun exposure value.
  String get sunExposureLabel {
    switch (sunExposure) {
      case 'full_sun':
        return 'Full Sun';
      case 'partial_shade':
        return 'Partial Shade';
      case 'full_shade':
        return 'Full Shade';
      default:
        return sunExposure;
    }
  }

  /// Returns a user-friendly label for the soil type value.
  String get soilTypeLabel {
    switch (soilType) {
      case 'clay':
        return 'Clay';
      case 'loam':
        return 'Loam';
      case 'sandy':
        return 'Sandy';
      case 'silt':
        return 'Silt';
      case 'peat':
        return 'Peat';
      case 'chalk':
        return 'Chalk';
      default:
        return soilType;
    }
  }

  /// Area in square centimetres.
  double get areaSqCm => widthCm * heightCm;

  /// Area in square metres.
  double get areaSqM => areaSqCm / 10000;

  ManualBed copyWith({
    String? id,
    String? name,
    double? widthCm,
    double? heightCm,
    String? sunExposure,
    String? soilType,
    Rect? rect,
    Color? color,
  }) {
    return ManualBed(
      id: id ?? this.id,
      name: name ?? this.name,
      widthCm: widthCm ?? this.widthCm,
      heightCm: heightCm ?? this.heightCm,
      sunExposure: sunExposure ?? this.sunExposure,
      soilType: soilType ?? this.soilType,
      rect: rect ?? this.rect,
      color: color ?? this.color,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ManualBed && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ManualBed(id: $id, name: $name, ${widthCm}x$heightCm cm, '
      'sun: $sunExposure, soil: $soilType)';
}
