import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { COLLECTIONS, NOTIFICATION_TYPE, REGION, REMINDER_WINDOW_HOURS, STATUS } from "./config";
import { db } from "./firebase";
import { createNotificationsInTransaction, formatDateTime, notifyOffice, officeRecipients } from "./notifications";

function toDate(value: unknown): Date | null {
  return value instanceof Timestamp ? value.toDate() : null;
}

function withNotes(message: string, notes: unknown): string {
  return typeof notes === "string" && notes.trim() ? `${message} Instructions: ${notes.trim()}` : message;
}

/** Notifies the office when the Collector creates a schedule. */
export const onScheduleCreated = onDocumentCreated(
  { document: `${COLLECTIONS.schedules}/{scheduleId}`, region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const when = toDate(data.collectionDate);
    await notifyOffice(data.officeId, event.id, {
      title: "New garbage collection scheduled",
      message: withNotes(`A garbage collection is scheduled for ${when ? formatDateTime(when) : "an upcoming date"}.`, data.notes),
      notificationType: NOTIFICATION_TYPE.scheduleCreated,
      relatedId: event.params.scheduleId,
    });
  },
);

/**
 * Notifies the office about cancellations, reschedules and instruction
 * changes. Transitions made by backend code (completed, upcoming) and the
 * Collector starting a collection (in progress) are not announced here.
 */
export const onScheduleUpdated = onDocumentUpdated(
  { document: `${COLLECTIONS.schedules}/{scheduleId}`, region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const statusChanged = before.status !== after.status;
    if (statusChanged && [STATUS.completed, STATUS.upcoming, STATUS.inProgress].includes(after.status)) return;

    const beforeDate = toDate(before.collectionDate);
    const afterDate = toDate(after.collectionDate);
    const dateChanged = beforeDate?.getTime() !== afterDate?.getTime();
    const notesChanged = (before.notes ?? "") !== (after.notes ?? "");
    const reason = typeof after.statusNote === "string" && after.statusNote ? ` Reason: ${after.statusNote}` : "";
    const scheduleId = event.params.scheduleId;

    if (statusChanged && after.status === STATUS.cancelled) {
      await notifyOffice(after.officeId, event.id, {
        title: "Garbage collection cancelled",
        message: `The collection scheduled for ${afterDate ? formatDateTime(afterDate) : "the planned date"} has been cancelled.${reason}`,
        notificationType: NOTIFICATION_TYPE.scheduleCancelled,
        relatedId: scheduleId,
      });
    } else if (dateChanged && afterDate) {
      await notifyOffice(after.officeId, event.id, {
        title: "Garbage collection rescheduled",
        message: `Your collection has been moved${beforeDate ? ` from ${formatDateTime(beforeDate)}` : ""} to ${formatDateTime(afterDate)}.${reason}`,
        notificationType: NOTIFICATION_TYPE.scheduleRescheduled,
        relatedId: scheduleId,
      });
    } else if (notesChanged) {
      await notifyOffice(after.officeId, event.id, {
        title: "Collection instructions updated",
        message: withNotes(
          `The Collector updated the instructions for your collection on ${afterDate ? formatDateTime(afterDate) : "the planned date"}.`,
          after.notes,
        ),
        notificationType: NOTIFICATION_TYPE.scheduleUpdated,
        relatedId: scheduleId,
      });
    }
  },
);

/**
 * Every 30 minutes: pending collections due within the reminder window are
 * marked "upcoming" and their office receives a reminder (once per date).
 * This never creates schedules.
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
        const when = toDate(s.collectionDate)!;
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
