/**
 * E-Labay optional Cloud Functions (Blaze plan only).
 *
 * The app works fully on the free Spark plan: assessments, points, account
 * provisioning and notifications are written by the app and verified by
 * Firestore security rules. Deploy these functions after upgrading to Blaze
 * to add:
 *   onNotificationCreated    push every in-app notification via FCM, including
 *                            when the app is closed
 *   sendCollectionReminders  every 30 minutes, remind offices of pickups due
 *                            within 24 hours (on Spark the Collector's app does
 *                            this when it opens)
 */
import { setGlobalOptions } from "firebase-functions/v2";

import { REGION } from "./config";

setGlobalOptions({ region: REGION, maxInstances: 10 });

export { onNotificationCreated } from "./notifications";
export { sendCollectionReminders } from "./schedules";
