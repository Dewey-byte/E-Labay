import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { COLLECTIONS, NOTIFICATION_TYPE, REGION, REMINDER_WINDOW_HOURS, STATUS } from "./config";
import { db } from "./firebase";
import { createNotificationsInTransaction, formatDateTime, officeRecipients } from "./notifications";

function withNotes(message: string, notes: unknown): string {
  return typeof notes === "string" && notes.trim() ? `${message} Instructions: ${notes.trim()}` : message;
}

/**
 * Every 30 minutes: pending collections due within the reminder window are
 * marked "upcoming" and their office receives a reminder, once per schedule.
 * Uses the same notification ids as the app's reminder check
 * (`reminder_{scheduleId}_{collectionDateMillis}_{uid}`) so the two never
 * duplicate. This never creates schedules.
 */
export const sendCollectionReminders = onSchedule(
  { schedule: "every 30 minutes", region: REGION },
  async () => {
    const now = Timestamp.now();
    const windowEnd = Timestamp.fromMillis(now.toMillis() + REMINDER_WINDOW_HOURS * 3600 * 1000);
    const due = await db
      .collection(COLLECTIONS.schedules)
      .where("status", "in", [STATUS.scheduled, STATUS.rescheduled])
      .where("collectionDate", ">=", now)
      .where("collectionDate", "<=", windowEnd)
      .get();

    let sent = 0;
    for (const doc of due.docs) {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        const s = snap.data();
        if (!s || ![STATUS.scheduled, STATUS.rescheduled].includes(s.status) || s.reminderSent === true) return;
        const recipients = await officeRecipients(s.officeId, tx);
        const when = (s.collectionDate as Timestamp).toDate();
        tx.update(doc.ref, {
          status: STATUS.upcoming,
          reminderSent: true,
          reminderSentAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        createNotificationsInTransaction(tx, recipients, s.officeId, `reminder_${doc.id}_${when.getTime()}`, {
          title: "Upcoming garbage collection",
          message: withNotes(
            `Reminder: your garbage collection is on ${formatDateTime(when)}. Please have your waste properly segregated.`,
            s.notes,
          ),
          notificationType: NOTIFICATION_TYPE.scheduleReminder,
          relatedId: doc.id,
        });
        sent++;
      });
    }
    logger.info("Collection reminders processed", { due: due.size, sent });
  },
);
