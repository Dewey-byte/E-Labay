import { FieldValue, Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { CAMPUS_TIME_ZONE, COLLECTIONS, REGION, ROLE } from "./config";
import { db, messaging } from "./firebase";

export interface NotificationPayload {
  title: string;
  message: string;
  notificationType: string;
  relatedId: string;
}

/** Active Faculty Office accounts linked to an office. */
export async function officeRecipients(officeId: string, tx?: Transaction): Promise<string[]> {
  const query = db
    .collection(COLLECTIONS.users)
    .where("officeId", "==", officeId)
    .where("role", "==", ROLE.faculty)
    .where("isActive", "==", true);
  const snap = tx ? await tx.get(query) : await query.get();
  return snap.docs.map((d) => d.id);
}

function notificationData(recipientId: string, officeId: string, payload: NotificationPayload, id: string) {
  return {
    notificationId: id,
    recipientId,
    recipientRole: ROLE.faculty,
    officeId,
    title: payload.title,
    message: payload.message,
    notificationType: payload.notificationType,
    relatedId: payload.relatedId,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Writes one notification per recipient inside a transaction. Notification
 * ids are deterministic (`{key}_{uid}`), so retries never duplicate them.
 */
export function createNotificationsInTransaction(
  tx: Transaction,
  recipients: string[],
  officeId: string,
  key: string,
  payload: NotificationPayload,
): void {
  for (const uid of recipients) {
    const id = `${key}_${uid}`;
    tx.set(db.collection(COLLECTIONS.notifications).doc(id), notificationData(uid, officeId, payload, id));
  }
}

/**
 * Notifies all accounts of an office outside a transaction (Firestore
 * triggers). `key` should be the trigger's event id so redelivered events are
 * idempotent.
 */
export async function notifyOffice(officeId: string, key: string, payload: NotificationPayload): Promise<void> {
  const recipients = await officeRecipients(officeId);
  await Promise.all(
    recipients.map(async (uid) => {
      const id = `${key}_${uid}`;
      try {
        await db.collection(COLLECTIONS.notifications).doc(id).create(notificationData(uid, officeId, payload, id));
      } catch (e) {
        // ALREADY_EXISTS (6): the event was redelivered; nothing to do.
        if ((e as { code?: number }).code !== 6) throw e;
      }
    }),
  );
}

export function formatDateTime(date: Date): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: CAMPUS_TIME_ZONE.value(),
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

const INVALID_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

/**
 * Sends an FCM push for every notification document created, to all devices
 * registered by the recipient (unless they disabled push). Invalid tokens are
 * removed.
 */
export const onNotificationCreated = onDocumentCreated(
  { document: `${COLLECTIONS.notifications}/{notificationId}`, region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const recipientId = data.recipientId as string;

    const userSnap = await db.collection(COLLECTIONS.users).doc(recipientId).get();
    const user = userSnap.data();
    if (!user || user.isActive === false || user.pushEnabled === false) return;

    const tokenSnap = await userSnap.ref.collection(COLLECTIONS.fcmTokens).get();
    const tokens = tokenSnap.docs.map((d) => d.id);
    if (tokens.length === 0) return;

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: { title: data.title, body: data.message },
      data: {
        notificationId: event.params.notificationId,
        type: String(data.notificationType ?? ""),
        relatedId: String(data.relatedId ?? ""),
      },
      android: { priority: "high", notification: { sound: "default" } },
      apns: { payload: { aps: { sound: "default" } } },
    });

    const stale: Promise<unknown>[] = [];
    response.responses.forEach((r, i) => {
      if (!r.success && r.error && INVALID_TOKEN_CODES.has(r.error.code)) {
        stale.push(tokenSnap.docs[i].ref.delete());
      }
    });
    await Promise.all(stale);
    logger.info("Push sent", {
      notificationId: event.params.notificationId,
      success: response.successCount,
      failed: response.failureCount,
      removedTokens: stale.length,
    });
  },
);
