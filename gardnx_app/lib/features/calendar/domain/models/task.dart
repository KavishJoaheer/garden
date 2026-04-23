import 'package:flutter/material.dart';
import 'package:gardnx_app/config/constants/firebase_constants.dart';

enum TaskPriority { low, medium, high }

extension TaskPriorityExt on TaskPriority {
  String get value {
    switch (this) {
      case TaskPriority.low:
        return 'low';
      case TaskPriority.medium:
        return 'medium';
      case TaskPriority.high:
        return 'high';
    }
  }

  String get label {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
    }
  }

  Color get color {
    switch (this) {
      case TaskPriority.low:
        return Colors.blue;
      case TaskPriority.medium:
        return Colors.orange;
      case TaskPriority.high:
        return Colors.red;
    }
  }

  static TaskPriority fromValue(String value) {
    switch (value) {
      case 'high':
        return TaskPriority.high;
      case 'medium':
        return TaskPriority.medium;
      default:
        return TaskPriority.low;
    }
  }
}

class PlantingTask {
  final String id;
  final String gardenId;
  final String? bedId;
  final String? bedName;
  final String? plantId;
  final String? plantName;
  final String? userId;
  final String description;
  final DateTime dueDate;
  final String taskType; // 'sow', 'transplant', 'harvest', 'water', etc.
  final bool isCompleted;
  final String priority; // 'low', 'medium', 'high'
  final DateTime? completedAt;

  const PlantingTask({
    required this.id,
    required this.gardenId,
    this.bedId,
    this.bedName,
    this.plantId,
    this.plantName,
    this.userId,
    required this.description,
    required this.dueDate,
    required this.taskType,
    this.isCompleted = false,
    this.priority = 'medium',
    this.completedAt,
  });

  bool get isOverdue =>
      !isCompleted &&
      dueDate.isBefore(DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day));

  /// Dual-read: accepts either camelCase (canonical) or snake_case (legacy).
  factory PlantingTask.fromJson(Map<String, dynamic> json) {
    final dueStr = readField<String>(json, 'dueDate', 'due_date');
    final completedStr =
        readField<String>(json, 'completedAt', 'completed_at');
    // Older docs wrote `is_completed`; canonical is `completed`.
    final completed = (json['completed'] as bool?) ??
        (json['is_completed'] as bool?) ??
        false;
    return PlantingTask(
      id: json['id'] as String? ?? '',
      gardenId: readField<String>(json, 'gardenId', 'garden_id') ?? '',
      bedId: readField<String>(json, 'bedId', 'bed_id'),
      bedName: readField<String>(json, 'bedName', 'bed_name'),
      plantId: readField<String>(json, 'plantId', 'plant_id'),
      plantName: readField<String>(json, 'plantName', 'plant_name'),
      userId: readField<String>(json, 'userId', 'user_id'),
      description: json['description'] as String? ?? '',
      dueDate: DateTime.parse(dueStr ?? DateTime.now().toIso8601String()),
      taskType: readField<String>(json, 'taskType', 'task_type') ?? 'general',
      isCompleted: completed,
      priority: json['priority'] as String? ?? 'medium',
      completedAt:
          completedStr != null ? DateTime.tryParse(completedStr) : null,
    );
  }

  /// Canonical camelCase write. Callers must NOT persist any snake_case keys.
  Map<String, dynamic> toJson() => {
        'id': id,
        FirebaseConstants.fieldGardenId: gardenId,
        FirebaseConstants.fieldBedId: bedId,
        FirebaseConstants.fieldBedName: bedName,
        FirebaseConstants.fieldPlantId: plantId,
        FirebaseConstants.fieldPlantName: plantName,
        if (userId != null) FirebaseConstants.fieldUserId: userId,
        'description': description,
        FirebaseConstants.fieldDueDate: dueDate.toIso8601String(),
        FirebaseConstants.fieldTaskType: taskType,
        FirebaseConstants.fieldCompleted: isCompleted,
        'priority': priority,
        FirebaseConstants.fieldCompletedAt: completedAt?.toIso8601String(),
      };

  PlantingTask copyWith({
    String? id,
    String? gardenId,
    String? bedId,
    String? bedName,
    String? plantId,
    String? plantName,
    String? userId,
    String? description,
    DateTime? dueDate,
    String? taskType,
    bool? isCompleted,
    String? priority,
    DateTime? completedAt,
  }) {
    return PlantingTask(
      id: id ?? this.id,
      gardenId: gardenId ?? this.gardenId,
      bedId: bedId ?? this.bedId,
      bedName: bedName ?? this.bedName,
      plantId: plantId ?? this.plantId,
      plantName: plantName ?? this.plantName,
      userId: userId ?? this.userId,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      taskType: taskType ?? this.taskType,
      isCompleted: isCompleted ?? this.isCompleted,
      priority: priority ?? this.priority,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PlantingTask && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
