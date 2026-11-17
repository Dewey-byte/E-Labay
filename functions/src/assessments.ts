import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import {
  COLLECTIONS,
  MAX_EVIDENCE_PHOTOS,
  MAX_REMARKS_LENGTH,
  NOTIFICATION_TYPE,
  PENDING_STATUSES,
  REGION,
  SCORING_CONFIG_PATH,
  STATUS,
} from "./config";
import { db } from "./firebase";
import { asInvalidArgument, requireCollector, requireId } from "./guards";
import { createNotificationsInTransaction, formatDateTime, officeRecipients } from "./notifications";
import {
  CATEGORIES,
  cleanString,
  parseScoringConfig,
  scoreAssessment,
  validateEvidenceUrls,
  validateSegregationResults,
} from "./scoring";

/** Transaction id for a collection — one per collection, ever. */
export const transactionIdFor = (collectionId: string) => `collection_${collectionId}`;

/**
 * Collector-only. Validates a waste segregation assessment and, in a single
 * Firestore transaction:
 *  1. creates `collections/{scheduleId}` (doc id = schedule id),
 *  2. creates `point_transactions/collection_{scheduleId}`,
 *  3. increments the office totals that drive the leaderboard,
 *  4. marks the schedule completed,
 *  5. creates the office's "completed" and "points awarded" notifications.
 * Deterministic ids make duplicate submissions and double awards impossible.
 *
 * Input: `{ scheduleId, segregationResults: {category: result}, remarks?, evidenceImageUrls? }`
 */
export const submitCollectionAssessment = onCall({ region: REGION }, async (request) => {
  const collector = await requireCollector(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const scheduleId = requireId(data.scheduleId, "scheduleId");
  const results = asInvalidArgument(() => validateSegregationResults(data.segregationResults));
  const remarks = asInvalidArgument(() =>
    cleanString(data.remarks, "Remarks", { max: MAX_REMARKS_LENGTH, required: false }),
  );
  const allowLocalUrls = process.env.FUNCTIONS_EMULATOR === "true";

  const scheduleRef = db.collection(COLLECTIONS.schedules).doc(scheduleId);
  const collectionRef = db.collection(COLLECTIONS.collections).doc(scheduleId);
  const txRef = db.collection(COLLECTIONS.pointTransactions).doc(transactionIdFor(scheduleId));
  const configRef = db.doc(SCORING_CONFIG_PATH);

  const outcome = await db.runTransaction(async (tx) => {
    // ---- Reads (all before any write) ----
    const [scheduleSnap, existingCollection, existingTx, configSnap] = await Promise.all([
      tx.get(scheduleRef),
      tx.get(collectionRef),
      tx.get(txRef),
      tx.get(configRef),
    ]);
    if (!scheduleSnap.exists) throw new HttpsError("not-found", "Schedule not found.");
    const schedule = scheduleSnap.data()!;
    if (existingCollection.exists || existingTx.exists || schedule.status === STATUS.completed) {
      throw new HttpsError("already-exists", "This collection has already been assessed.");
    }
    if (schedule.status === STATUS.cancelled) {
      throw new HttpsError("failed-precondition", "This collection was cancelled.");
    }
    if (!PENDING_STATUSES.includes(schedule.status)) {
      throw new HttpsError("failed-precondition", "This collection cannot be assessed.");
    }
    const officeId = schedule.officeId as string;
    const officeRef = db.collection(COLLECTIONS.offices).doc(officeId);
    const officeSnap = await tx.get(officeRef);
    if (!officeSnap.exists) throw new HttpsError("not-found", "The office for this schedule no longer exists.");
    const recipients = await officeRecipients(officeId, tx);

    const evidenceImageUrls = asInvalidArgument(() =>
      validateEvidenceUrls(data.evidenceImageUrls, officeId, scheduleId, MAX_EVIDENCE_PHOTOS, allowLocalUrls),
    );
    const scoring = parseScoringConfig(configSnap.data());
    const score = scoreAssessment(results, scoring);
    const officeName = (officeSnap.data()!.officeName as string) ?? schedule.officeName;
    const now = FieldValue.serverTimestamp();

    // ---- Writes ----
    tx.create(collectionRef, {
      collectionId: scheduleId,
      scheduleId,
      officeId,
      officeName,
      collectorId: collector.uid,
      collectorName: collector.name,
      segregationResults: results,
      properCount: score.properCount,
      improperCount: score.improperCount,
      applicableCount: score.applicableCount,
      pointsAwarded: score.points,
      maxPoints: score.maxPoints,
      scoring,
      remarks,
      evidenceImageUrls,
      scheduledDate: schedule.collectionDate ?? null,
      collectedAt: now,
      createdAt: now,
    });

    tx.create(txRef, {
      transactionId: txRef.id,
      officeId,
      officeName,
      collectionId: scheduleId,
      scheduleId,
      pointsAwarded: score.points,
      transactionType: "collection_assessment",
      properCount: score.properCount,
      applicableCount: score.applicableCount,
      remarks,
      collectorId: collector.uid,
      collectorName: collector.name,
      assessmentDate: now,
      createdAt: now,
    });

    const officeUpdate: Record<string, unknown> = {
      totalPoints: FieldValue.increment(score.points),
      totalCollections: FieldValue.increment(1),
      totalProperSegregations: FieldValue.increment(score.properCount),
      totalAssessments: FieldValue.increment(score.applicableCount),
      lastCollectionAt: now,
      lastPointsAwarded: score.points,
      updatedAt: now,
    };
    for (const category of CATEGORIES) {
      const result = results[category];
      if (result === "proper" || result === "improper") {
        officeUpdate[`categoryStats.${category}.${result}`] = FieldValue.increment(1);
      }
    }
    tx.update(officeRef, officeUpdate);

    tx.update(scheduleRef, {
      status: STATUS.completed,
      collectionId: scheduleId,
      pointsAwarded: score.points,
      completedAt: now,
      updatedAt: now,
    });

    const when = schedule.collectionDate instanceof Timestamp ? formatDateTime(schedule.collectionDate.toDate()) : "today";
    const summary = `${score.properCount} of ${score.applicableCount} assessed categories were properly segregated`;
    createNotificationsInTransaction(tx, recipients, officeId, `completed_${scheduleId}`, {
      title: "Garbage collection completed",
      message: `Your collection scheduled for ${when} is complete. Assessment result: ${summary}.` +
        (remarks ? ` Collector's remarks: "${remarks}"` : ""),
      notificationType: NOTIFICATION_TYPE.collectionCompleted,
      relatedId: scheduleId,
    });
    createNotificationsInTransaction(tx, recipients, officeId, `points_${scheduleId}`, {
      title: score.points > 0 ? `You earned ${score.points} points!` : "No points this collection",
      message: score.points > 0
        ? `${officeName} earned ${score.points} of ${score.maxPoints} possible points for waste segregation.`
        : `${officeName} earned no points this time. Check the assessment to see how to improve.`,
      notificationType: NOTIFICATION_TYPE.pointsAwarded,
      relatedId: scheduleId,
    });

    return { officeId, score };
  });

  logger.info("Assessment submitted", {
    scheduleId,
    officeId: outcome.officeId,
    points: outcome.score.points,
    by: collector.uid,
  });
  return {
    collectionId: scheduleId,
    pointsAwarded: outcome.score.points,
    maxPoints: outcome.score.maxPoints,
  };
});
