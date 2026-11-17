/**
 * E-Labay Cloud Functions — the trusted backend.
 *
 * Callable (Collector only):
 *   provisionFacultyAccount, setAccountStatus,
 *   submitCollectionAssessment, recalculateLeaderboard
 * Firestore triggers:
 *   onScheduleCreated, onScheduleUpdated  -> office notifications
 *   onNotificationCreated                 -> FCM push
 * Scheduled:
 *   sendCollectionReminders               -> "upcoming" reminders
 */
import { setGlobalOptions } from "firebase-functions/v2";

import { REGION } from "./config";

setGlobalOptions({ region: REGION, maxInstances: 10 });

export { provisionFacultyAccount, setAccountStatus } from "./accounts";
export { submitCollectionAssessment } from "./assessments";
export { recalculateLeaderboard } from "./maintenance";
export { onNotificationCreated } from "./notifications";
export { onScheduleCreated, onScheduleUpdated, sendCollectionReminders } from "./schedules";
