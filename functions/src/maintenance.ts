import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onCall } from "firebase-functions/v2/https";

import { COLLECTIONS, REGION } from "./config";
import { db } from "./firebase";
import { requireCollector } from "./guards";
import { CATEGORIES } from "./scoring";

/**
 * Collector-only consistency check: recomputes every office's leaderboard
 * totals from the permanent point-transaction ledger and collection records.
 * Each office is recomputed in its own transaction, so it serialises with
 * concurrent assessment submissions.
 */
export const recalculateLeaderboard = onCall({ region: REGION, timeoutSeconds: 300 }, async (request) => {
  const collector = await requireCollector(request);
  const offices = await db.collection(COLLECTIONS.offices).select().get();
  let corrected = 0;

  for (const office of offices.docs) {
    await db.runTransaction(async (tx) => {
      const officeSnap = await tx.get(office.ref);
      if (!officeSnap.exists) return;
      const [txSnap, collectionSnap] = await Promise.all([
        tx.get(db.collection(COLLECTIONS.pointTransactions).where("officeId", "==", office.id)),
        tx.get(db.collection(COLLECTIONS.collections).where("officeId", "==", office.id)),
      ]);

      const totalPoints = txSnap.docs.reduce((sum, d) => sum + (Number(d.data().pointsAwarded) || 0), 0);
      const categoryStats = Object.fromEntries(CATEGORIES.map((c) => [c, { proper: 0, improper: 0 }]));
      let proper = 0;
      let assessed = 0;
      let last: FirebaseFirestore.Timestamp | null = null;
      for (const doc of collectionSnap.docs) {
        const c = doc.data();
        proper += Number(c.properCount) || 0;
        assessed += Number(c.applicableCount) || 0;
        const results = (c.segregationResults ?? {}) as Record<string, string>;
        for (const category of CATEGORIES) {
          const r = results[category];
          if (r === "proper" || r === "improper") categoryStats[category][r]++;
        }
        if (c.collectedAt && (!last || c.collectedAt.toMillis() > last.toMillis())) last = c.collectedAt;
      }

      const current = officeSnap.data()!;
      if (
        current.totalPoints !== totalPoints ||
        current.totalCollections !== collectionSnap.size ||
        current.totalProperSegregations !== proper ||
        current.totalAssessments !== assessed
      ) {
        corrected++;
      }
      tx.update(office.ref, {
        totalPoints,
        totalCollections: collectionSnap.size,
        totalProperSegregations: proper,
        totalAssessments: assessed,
        categoryStats,
        lastCollectionAt: last,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  logger.info("Leaderboard recalculated", { offices: offices.size, corrected, by: collector.uid });
  return { officesUpdated: offices.size, corrected };
});
