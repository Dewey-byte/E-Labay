import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The two E-Labay roles. Stored as `users.role` and as a custom auth claim.
enum UserRole {
  collector('collector', 'Collector'),
  faculty('faculty', 'Faculty Office');

  const UserRole(this.value, this.label);
  final String value;
  final String label;

  static UserRole? tryParse(String? value) {
    for (final role in values) {
      if (role.value == value) return role;
    }
    return null;
  }
}

enum ScheduleStatus {
  scheduled('scheduled', 'Scheduled', AppColors.info, Icons.event_outlined),
  upcoming('upcoming', 'Upcoming', AppColors.warning, Icons.notifications_active_outlined),
  inProgress('in_progress', 'In Progress', AppColors.progress, Icons.local_shipping_outlined),
  completed('completed', 'Completed', AppColors.success, Icons.check_circle_outline),
  cancelled('cancelled', 'Cancelled', AppColors.danger, Icons.cancel_outlined),
  rescheduled('rescheduled', 'Rescheduled', AppColors.rescheduled, Icons.update);

  const ScheduleStatus(this.value, this.label, this.color, this.icon);
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  /// Statuses that still await collection.
  static const pending = [scheduled, upcoming, inProgress, rescheduled];

  /// Statuses that belong in the collection history.
  static const history = [completed, cancelled];

  bool get isPending => pending.contains(this);
  bool get isFinal => this == completed || this == cancelled;

  static ScheduleStatus parse(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return scheduled;
  }
}

/// Waste segregation categories assessed on every collection.
/// Keys must match `CATEGORIES` in `functions/src/scoring.ts`.
enum WasteCategory {
  biodegradable(
    'biodegradable',
    'Biodegradable',
    'Food scraps, leaves, paper towels, other compostables',
    Icons.eco_outlined,
    Color(0xFF3E8E41),
  ),
  nonBiodegradable(
    'non_biodegradable',
    'Non-biodegradable',
    'Plastic wrappers, styrofoam, sachets, rubber',
    Icons.delete_outline,
    Color(0xFF5B6770),
  ),
  recyclable(
    'recyclable',
    'Recyclable',
    'Clean bottles, cans, paper, cardboard',
    Icons.recycling,
    Color(0xFF2F6FDE),
  ),
  residual(
    'residual',
    'Residual Waste',
    'Soiled tissues, sanitary items, broken items',
    Icons.delete_sweep_outlined,
    Color(0xFFB8733A),
  );

  const WasteCategory(this.key, this.label, this.examples, this.icon, this.color);
  final String key;
  final String label;
  final String examples;
  final IconData icon;
  final Color color;

  static WasteCategory? tryParse(String? key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

enum SegregationResult {
  proper('proper', 'Properly Segregated', 'Proper', AppColors.success, Icons.check_circle),
  improper('improper', 'Improperly Segregated', 'Improper', AppColors.danger, Icons.cancel),
  notApplicable('not_applicable', 'Not Applicable', 'N/A', AppColors.textMuted, Icons.remove_circle_outline);

  const SegregationResult(this.value, this.label, this.shortLabel, this.color, this.icon);
  final String value;
  final String label;
  final String shortLabel;
  final Color color;
  final IconData icon;

  static SegregationResult? tryParse(String? value) {
    for (final r in values) {
      if (r.value == value) return r;
    }
    return null;
  }
}

enum NotificationType {
  scheduleCreated('schedule_created', 'New schedule', Icons.event_available_outlined, AppColors.info),
  scheduleReminder('schedule_reminder', 'Reminder', Icons.alarm, AppColors.warning),
  scheduleRescheduled('schedule_rescheduled', 'Rescheduled', Icons.update, AppColors.rescheduled),
  scheduleCancelled('schedule_cancelled', 'Cancelled', Icons.event_busy_outlined, AppColors.danger),
  scheduleUpdated('schedule_updated', 'Schedule update', Icons.edit_calendar_outlined, AppColors.info),
  collectionCompleted('collection_completed', 'Collection completed', Icons.task_alt, AppColors.success),
  pointsAwarded('points_awarded', 'Points awarded', Icons.emoji_events_outlined, AppColors.gold),
  general('general', 'Notice', Icons.notifications_none, AppColors.textSecondary);

  const NotificationType(this.value, this.label, this.icon, this.color);
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  /// Whether the related record is a schedule (otherwise a collection).
  bool get relatesToSchedule =>
      this == scheduleCreated ||
      this == scheduleReminder ||
      this == scheduleRescheduled ||
      this == scheduleCancelled ||
      this == scheduleUpdated;

  bool get relatesToCollection => this == collectionCompleted || this == pointsAwarded;

  static NotificationType parse(String? value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return general;
  }
}
