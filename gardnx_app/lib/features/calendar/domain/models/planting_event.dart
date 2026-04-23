import 'package:flutter/material.dart';
import 'package:gardnx_app/config/constants/firebase_constants.dart';

enum PlantingEventType { sow, transplant, harvest, water, fertilize, general }

extension PlantingEventTypeExt on PlantingEventType {
  String get label {
    switch (this) {
      case PlantingEventType.sow:
        return 'Sow';
      case PlantingEventType.transplant:
        return 'Transplant';
      case PlantingEventType.harvest:
        return 'Harvest';
      case PlantingEventType.water:
        return 'Water';
      case PlantingEventType.fertilize:
        return 'Fertilize';
      case PlantingEventType.general:
        return 'General';
    }
  }

  String get value {
    switch (this) {
      case PlantingEventType.sow:
        return 'sow';
      case PlantingEventType.transplant:
        return 'transplant';
      case PlantingEventType.harvest:
        return 'harvest';
      case PlantingEventType.water:
        return 'water';
      case PlantingEventType.fertilize:
        return 'fertilize';
      case PlantingEventType.general:
        return 'general';
    }
  }

  Color get color {
    switch (this) {
      case PlantingEventType.sow:
        return Colors.green;
      case PlantingEventType.transplant:
        return Colors.blue;
      case PlantingEventType.harvest:
        return Colors.orange;
      case PlantingEventType.water:
        return Colors.cyan;
      case PlantingEventType.fertilize:
        return Colors.purple;
      case PlantingEventType.general:
        return Colors.grey;
    }
  }

  IconData get icon {
    switch (this) {
      case PlantingEventType.sow:
        return Icons.grass;
      case PlantingEventType.transplant:
        return Icons.swap_horiz;
      case PlantingEventType.harvest:
        return Icons.cut;
      case PlantingEventType.water:
        return Icons.water_drop;
      case PlantingEventType.fertilize:
        return Icons.science;
      case PlantingEventType.general:
        return Icons.event;
    }
  }

  static PlantingEventType fromValue(String value) {
    switch (value) {
      case 'sow':
        return PlantingEventType.sow;
      case 'transplant':
        return PlantingEventType.transplant;
      case 'harvest':
        return PlantingEventType.harvest;
      case 'water':
        return PlantingEventType.water;
      case 'fertilize':
        return PlantingEventType.fertilize;
      default:
        return PlantingEventType.general;
    }
  }
}

class PlantingEvent {
  final String id;
  final String gardenId;
  final String? bedId;
  final String? bedName;
  final String? plantId;
  final String plantName;
  final String? userId;
  final PlantingEventType eventType;
  final DateTime date;
  final String? notes;
  final bool isCompleted;

  const PlantingEvent({
    required this.id,
    required this.gardenId,
    this.bedId,
    this.bedName,
    this.plantId,
    required this.plantName,
    this.userId,
    required this.eventType,
    required this.date,
    this.notes,
    this.isCompleted = false,
  });

  /// Dual-read: accepts camelCase (canonical) or snake_case (legacy).
  factory PlantingEvent.fromJson(Map<String, dynamic> json) {
    final eventTypeStr =
        readField<String>(json, 'eventType', 'event_type') ?? 'general';
    final completed = (json['completed'] as bool?) ??
        (json['is_completed'] as bool?) ??
        false;
    return PlantingEvent(
      id: json['id'] as String? ?? '',
      gardenId: readField<String>(json, 'gardenId', 'garden_id') ?? '',
      bedId: readField<String>(json, 'bedId', 'bed_id'),
      bedName: readField<String>(json, 'bedName', 'bed_name'),
      plantId: readField<String>(json, 'plantId', 'plant_id'),
      plantName: readField<String>(json, 'plantName', 'plant_name') ?? '',
      userId: readField<String>(json, 'userId', 'user_id'),
      eventType: PlantingEventTypeExt.fromValue(eventTypeStr),
      date: DateTime.parse(json['date'] as String),
      notes: json['notes'] as String?,
      isCompleted: completed,
    );
  }

  /// Canonical camelCase write.
  Map<String, dynamic> toJson() => {
        'id': id,
        FirebaseConstants.fieldGardenId: gardenId,
        FirebaseConstants.fieldBedId: bedId,
        FirebaseConstants.fieldBedName: bedName,
        FirebaseConstants.fieldPlantId: plantId,
        FirebaseConstants.fieldPlantName: plantName,
        if (userId != null) FirebaseConstants.fieldUserId: userId,
        FirebaseConstants.fieldEventType: eventType.value,
        'date': date.toIso8601String(),
        'notes': notes,
        FirebaseConstants.fieldCompleted: isCompleted,
      };

  PlantingEvent copyWith({
    String? id,
    String? gardenId,
    String? bedId,
    String? bedName,
    String? plantId,
    String? plantName,
    String? userId,
    PlantingEventType? eventType,
    DateTime? date,
    String? notes,
    bool? isCompleted,
  }) {
    return PlantingEvent(
      id: id ?? this.id,
      gardenId: gardenId ?? this.gardenId,
      bedId: bedId ?? this.bedId,
      bedName: bedName ?? this.bedName,
      plantId: plantId ?? this.plantId,
      plantName: plantName ?? this.plantName,
      userId: userId ?? this.userId,
      eventType: eventType ?? this.eventType,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
