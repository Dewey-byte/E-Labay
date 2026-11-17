import { defineString } from "firebase-functions/params";

/** Region for the optional functions (match your Firestore location). */
export const REGION = "asia-southeast1";

/** Time zone used to format dates inside notification messages. */
export const CAMPUS_TIME_ZONE = defineString("CAMPUS_TIME_ZONE", {
  default: "Asia/Manila",
  description: "IANA time zone of the campus, used in notification text",
});

export const COLLECTIONS = {
  users: "users",
  offices: "offices",
  schedules: "schedules",
  collections: "collections",
  notifications: "notifications",
  pointTransactions: "point_transactions",
  config: "config",
  fcmTokens: "fcmTokens",
} as const;

export const ROLE = {
  collector: "collector",
  faculty: "faculty",
} as const;

export const STATUS = {
  scheduled: "scheduled",
  upcoming: "upcoming",
  inProgress: "in_progress",
  completed: "completed",
  cancelled: "cancelled",
  rescheduled: "rescheduled",
} as const;

export const NOTIFICATION_TYPE = {
  scheduleCreated: "schedule_created",
  scheduleReminder: "schedule_reminder",
  scheduleRescheduled: "schedule_rescheduled",
  scheduleCancelled: "schedule_cancelled",
  scheduleUpdated: "schedule_updated",
  collectionCompleted: "collection_completed",
  pointsAwarded: "points_awarded",
} as const;

/** Reminders go out once a pending collection is this close. */
export const REMINDER_WINDOW_HOURS = 24;

