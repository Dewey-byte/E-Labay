// Seeds the LOCAL Firebase emulators with demo data for trying E-Labay.
//
//   Terminal 1:  npm run emulators
//   Terminal 2:  npm run seed            (add --minimal for just the Collector)
//   App:         flutter run --dart-define=USE_FIREBASE_EMULATORS=true
//
// Demo accounts (emulator only):
//   Collector       collector@elabay.test / collector123
//   Faculty offices <name>@elabay.test    / office123
//
// Writes with the Admin SDK, producing the same document shapes and totals
// the app creates. Refuses to run against anything but local emulators.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";

import { readFileSync } from "node:fs";

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

// Same project id the app uses (from .firebaserc), so the app sees the data.
const PROJECT =
  process.env.GCLOUD_PROJECT ??
  (() => {
    try {
      return JSON.parse(readFileSync(".firebaserc", "utf8")).projects.default;
    } catch {
      return "demo-elabay";
    }
  })();
for (const host of [process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST]) {
  if (!/^(127\.0\.0\.1|localhost):/.test(host)) throw new Error(`Refusing to seed: ${host} is not local.`);
}

initializeApp({ projectId: PROJECT });
const auth = getAuth();
const db = getFirestore();
const minimal = process.argv.includes("--minimal");

const DAY = 24 * 3600 * 1000;
const at = (daysFromNow, hour, minute = 0) => {
  const d = new Date(Date.now() + daysFromNow * DAY);
  d.setHours(hour, minute, 0, 0);
  return d;
};
const hhmm = (d) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
const fmt = (d) => d.toLocaleString("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });

const OFFICES = [
  { officeName: "College of Engineering", building: "Engineering Building", email: "eng", quality: 0.9 },
  { officeName: "College of Education", building: "Education Building", email: "educ", quality: 0.75 },
  { officeName: "Registrar's Office", building: "Administration Building", email: "registrar", quality: 0.85 },
  { officeName: "College of Nursing", building: "Health Sciences Building", email: "nursing", quality: 0.6 },
  { officeName: "Accounting Office", building: "Administration Building", email: "accounting", quality: 0.45 },
];
const CATEGORIES = ["biodegradable", "non_biodegradable", "recyclable", "residual"];
const REMARKS = ["Great job keeping recyclables clean.", "Food waste found in the recyclables bin.", "Residual waste mixed with plastics.", "", "Bins clearly labeled — keep it up!"];
let seed = 7;
const random = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);

async function profile(email, password, data) {
  const user = await auth.createUser({ email, password, displayName: data.fullName });
  await db.doc(`users/${user.uid}`).set({
    uid: user.uid, email, profileImage: null, isActive: true, pushEnabled: true,
    createdAt: Timestamp.now(), updatedAt: Timestamp.now(), ...data,
  });
  return user.uid;
}

async function main() {
  if (await auth.getUserByEmail("collector@elabay.test").catch(() => null)) {
    console.log("Emulators already seeded. Restart the emulators to reseed.");
    return;
  }
  const collectorUid = await profile("collector@elabay.test", "collector123", { fullName: "Maria Santos", role: "collector", officeId: null });
  await db.doc("config/scoring").set({ properPoints: 10, improperPoints: 0, updatedBy: collectorUid, updatedAt: Timestamp.now() });
  console.log("Collector: collector@elabay.test / collector123");
  if (minimal) return;

  const notify = async (uid, officeId, key, type, title, message, relatedId, createdAt) => {
    const id = `${key}_${uid}`;
    await db.doc(`notifications/${id}`).set({
      notificationId: id, recipientId: uid, recipientRole: "faculty", officeId, title, message,
      notificationType: type, relatedId, isRead: createdAt.toMillis() < Date.now() - 2 * DAY, createdAt,
    });
  };

  const newSchedule = async (office, when, notes = "", extra = {}) => {
    const ref = db.collection("schedules").doc();
    const created = Timestamp.fromMillis(Math.min(Date.now(), when.getTime() - 3 * DAY));
    await ref.set({
      scheduleId: ref.id, officeId: office.officeId, officeName: office.officeName, building: office.building,
      collectorId: collectorUid, collectorName: "Maria Santos", collectionDate: Timestamp.fromDate(when),
      collectionTime: hhmm(when), notes, status: "scheduled", reminderSent: false,
      createdAt: created, updatedAt: created, ...extra,
    });
    await notify(office.uid, office.officeId, `created_${ref.id}`, "schedule_created", "New garbage collection scheduled",
      `A garbage collection is scheduled for ${fmt(when)}.${notes ? ` Instructions: ${notes}` : ""}`, ref.id, created);
    return ref;
  };

  for (const office of OFFICES) {
    const ref = db.collection("offices").doc();
    office.officeId = ref.id;
    office.totals = { totalPoints: 0, totalCollections: 0, totalProperSegregations: 0, totalAssessments: 0 };
    office.stats = Object.fromEntries(CATEGORIES.map((c) => [c, { proper: 0, improper: 0 }]));
    office.uid = await profile(`${office.email}@elabay.test`, "office123", {
      fullName: office.officeName, role: "faculty", officeId: ref.id, createdBy: collectorUid,
    });
    office.ref = ref;
    console.log(`Office:    ${office.email}@elabay.test / office123  (${office.officeName})`);
  }

  let assessed = 0;
  for (let daysAgo = 13; daysAgo >= 0; daysAgo--) {
    for (const office of OFFICES) {
      if (random() > 0.45) continue;
      const when = at(-daysAgo, 8 + Math.floor(random() * 8), random() > 0.5 ? 30 : 0);
      if (when.getTime() > Date.now()) continue;
      const schedule = await newSchedule(office, when);
      const results = Object.fromEntries(CATEGORIES.map((c) => [c, random() < 0.12 ? "not_applicable" : random() < office.quality ? "proper" : "improper"]));
      const proper = Object.values(results).filter((r) => r === "proper").length;
      const improper = Object.values(results).filter((r) => r === "improper").length;
      const points = proper * 10;
      const remarks = REMARKS[Math.floor(random() * REMARKS.length)];
      const ts = Timestamp.fromMillis(when.getTime() + 20 * 60 * 1000);
      const id = schedule.id;
      await db.doc(`collections/${id}`).set({
        collectionId: id, scheduleId: id, officeId: office.officeId, officeName: office.officeName,
        collectorId: collectorUid, collectorName: "Maria Santos", segregationResults: results,
        properCount: proper, improperCount: improper, applicableCount: proper + improper,
        pointsAwarded: points, maxPoints: (proper + improper) * 10, scoring: { properPoints: 10, improperPoints: 0 },
        remarks, evidenceImageUrls: [], scheduledDate: Timestamp.fromDate(when), collectedAt: ts, createdAt: ts,
      });
      await db.doc(`point_transactions/collection_${id}`).set({
        transactionId: `collection_${id}`, officeId: office.officeId, officeName: office.officeName,
        collectionId: id, scheduleId: id, pointsAwarded: points, transactionType: "collection_assessment",
        properCount: proper, applicableCount: proper + improper, remarks, collectorId: collectorUid,
        collectorName: "Maria Santos", assessmentDate: ts, createdAt: ts,
      });
      await schedule.update({ status: "completed", collectionId: id, pointsAwarded: points, completedAt: ts, updatedAt: ts });
      office.totals.totalPoints += points;
      office.totals.totalCollections += 1;
      office.totals.totalProperSegregations += proper;
      office.totals.totalAssessments += proper + improper;
      for (const c of CATEGORIES) if (results[c] !== "not_applicable") office.stats[c][results[c]] += 1;
      office.lastCollectionId = id;
      office.lastPointsAwarded = points;
      office.lastCollectionAt = ts;
      await notify(office.uid, office.officeId, `completed_${id}`, "collection_completed", "Garbage collection completed",
        `Your collection is complete. Assessment result: ${proper} of ${proper + improper} assessed categories were properly segregated.`, id, ts);
      await notify(office.uid, office.officeId, `points_${id}`, "points_awarded",
        points > 0 ? `You earned ${points} points!` : "No points this collection",
        `${office.officeName} earned ${points} of ${(proper + improper) * 10} possible points for waste segregation.`, id, ts);
      assessed++;
    }
  }

  for (const office of OFFICES) {
    await office.ref.set({
      officeId: office.officeId, officeName: office.officeName, building: office.building, description: "",
      ...office.totals, categoryStats: office.stats, createdBy: collectorUid,
      ...(office.lastCollectionId ? { lastCollectionId: office.lastCollectionId, lastPointsAwarded: office.lastPointsAwarded, lastCollectionAt: office.lastCollectionAt } : {}),
      createdAt: Timestamp.fromMillis(Date.now() - 20 * DAY), updatedAt: Timestamp.now(),
    });
  }

  await newSchedule(OFFICES[0], at(0, 15), "Please place bins outside the dean's office.");
  await newSchedule(OFFICES[1], at(0, 16, 30));
  await newSchedule(OFFICES[2], at(1, 9), "Separate shredded paper from other recyclables.");
  await newSchedule(OFFICES[3], at(1, 14));
  await newSchedule(OFFICES[4], at(2, 10), "The Collector will check the pantry bins too.");
  await newSchedule(OFFICES[0], at(4, 8, 30));
  const cancelled = await newSchedule(OFFICES[3], at(3, 11));
  await cancelled.update({ status: "cancelled", statusNote: "Campus-wide holiday", cancelledAt: Timestamp.now() });

  console.log(`Seeded ${OFFICES.length} offices, ${assessed} assessed collections and 7 upcoming schedules.`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
