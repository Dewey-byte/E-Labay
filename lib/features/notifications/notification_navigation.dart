import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../routes/app_routes.dart';

/// Opens the schedule or collection a notification refers to. Returns false
/// when the notification has no related record.
bool openNotificationTarget(BuildContext context, NotificationType type, String? relatedId) {
  if (relatedId == null || relatedId.isEmpty) return false;
  if (type.relatesToSchedule) {
    context.push(AppRoutes.facultySchedule(relatedId));
    return true;
  }
  if (type.relatesToCollection) {
    context.push(AppRoutes.facultyCollection(relatedId));
    return true;
  }
  return false;
}
