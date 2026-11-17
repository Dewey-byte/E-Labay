// Seeds the LOCAL Firebase emulators with demo data for trying E-Labay.
//
//   Terminal 1:  npm run emulators
//   Terminal 2:  npm run seed
//   App:         flutter run --dart-define=USE_FIREBASE_EMULATORS=true
//
// Demo accounts (emulator only):
//   Collector       collector@elabay.test / collector123
//   Faculty offices <name>@elabay.test    / office123
//
// Offices are provisioned and assessments submitted through the real Cloud
// Functions, so points, notifications and the leaderboard are produced
// exactly as in production. Refuses to run against anything but emulators.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";

import { initializeApp as initAdmin } from "firebase-admin/app";
import { getAuth as getAdminAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore as getAdminDb } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInWithEmailAndPassword } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";

const PROJECT = "demo-elabay";
if (!process.env.FIRESTORE_EMULATOR_HOST.startsWith("127.0.0.1") && !process.env.FIRESTORE_EMULATOR_HOST.startsWith("localhost")) {
  throw new Error("Refusing to seed: FIRESTORE_EMULATOR_HOST is not local.");
}

initAdmin({ projectId: PROJECT });
const adminAuth = getAdminAuth();
const db = getAdminDb();

const app = initializeApp({ projectId: PROJECT, apiKey: "demo-api-key" }, "seed");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const fns = getFunctions(app, "asia-southeast1");
connectFunctionsEmulator(fns, "127.0.0.1", 5001);
const call = (name, data) => httpsCallable(fns, name)(data).then((r) => r.data);

const DAY = 24 * 3600 * 1000;
const at = (daysFromNow, hour, minute = 0) => {
  const d = new Date(Date.now() + daysFromNow * DAY);
  d.setHours(hour, minute, 0, 0);
  return d;
};
const hhmm = (d) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;

const OFFICES = [
  { officeName: "College of Engineering", building: "Engineering Building", email: "eng", quality: 0.9 },
  { officeName: "College of Education", building: "Education Building", email: "educ", quality: 0.75 },
  { officeName: "Registrar's Office", building: "Administration Building", email: "registrar", quality: 0.85 },
  { officeName: "College of Nursing", building: "Health Sciences Building", email: "nursing", quality: 0.6 },
  { officeName: "Accounting Office", building: "Administration Building", email: "accounting", quality: 0.45 },
];
const CATEGORIES = ["biodegradable", "non_biodegradable", "recyclable", "residual"];
const REMARKS = [
  "Great job keeping recyclables clean.",
  "Food waste found in the recyclables bin.",
  "Residual waste mixed with plastics.",
  "",
  "Bins clearly labeled — keep it up!",
];

let seed = 7;
const random = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);

async function main() {
  if ((await adminAuth.getUserByEmail("collector@elabay.test").catch(() => null)) !== null) {
    console.log("Emulators already seeded. Restart the emulators to reseed.");
    return;
  }

  // Collector (trusted admin process, as create-collector.js does in production).
  const collector = await adminAuth.createUser({ email: "collector@elabay.test", password: "collector123", displayName: "Maria Santos" });
  await adminAuth.setCustomUserClaims(collector.uid, { role: "collector", officeId: null });
  await db.doc(`users/${collector.uid}`).set({
    uid: collector.uid, fullName: "Maria Santos", email: "collector@elabay.test", role: "collector",
    officeId: null, profileImage: null, isActive: true, pushEnabled: true,
    createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
  await db.doc("config/scoring").set({ properPoints: 10, improperPoints: 0, updatedBy: collector.uid, updatedAt: Timestamp.now() });
  await signInWithEmailAndPassword(auth, "collector@elabay.test", "collector123");
  console.log("Collector: collector@elabay.test / collector123");

  for (const office of OFFICES) {
    const { officeId } = await call("provisionFacultyAccount", {
      office: { officeName: office.officeName, building: office.building, description: "" },
      account: { fullName: office.officeName, email: `${office.email}@elabay.test`, password: "office123" },
    });
    office.officeId = officeId;
    console.log(`Office:    ${office.email}@elabay.test / office123  (${office.officeName})`);
  }

  const schedule = async (office, when, status = "scheduled", notes = "") => {
    const ref = db.collection("schedules").doc();
    await ref.set({
      scheduleId: ref.id, officeId: office.officeId, officeName: office.officeName, building: office.building,
      collectorId: collector.uid, collectorName: "Maria Santos", collectionDate: Timestamp.fromDate(when),
      collectionTime: hhmm(when), notes, status, reminderSent: false,
      createdAt: Timestamp.fromMillis(when.getTime() - 3 * DAY), updatedAt: Timestamp.now(),
    });
    return ref;
  };

  // Past, assessed collections over the last two weeks.
  let assessed = 0;
  for (let daysAgo = 13; daysAgo >= 0; daysAgo -= 1) {
    for (const office of OFFICES) {
      if (random() > 0.45) continue;
      const when = at(-daysAgo, 8 + Math.floor(random() * 8), random() > 0.5 ? 30 : 0);
      if (when.getTime() > Date.now()) continue;
      const ref = await schedule(office, when);
      const results = Object.fromEntries(
        CATEGORIES.map((c) => [c, random() < 0.12 ? "not_applicable" : random() < office.quality ? "proper" : "improper"]),
      );
      await call("submitCollectionAssessment", {
        scheduleId: ref.id,
        segregationResults: results,
        remarks: REMARKS[Math.floor(random() * REMARKS.length)],
      });
      // Backdate the server timestamps so charts show a realistic history.
      const ts = Timestamp.fromDate(new Date(when.getTime() + 20 * 60 * 1000));
      await Promise.all([
        db.doc(`collections/${ref.id}`).update({ collectedAt: ts, createdAt: ts }),
        db.doc(`point_transactions/collection_${ref.id}`).update({ assessmentDate: ts, createdAt: ts }),
        ref.update({ completedAt: ts }),
      ]);
      assessed++;
    }
  }

  // Upcoming, cancelled and today's schedules.
  await schedule(OFFICES[0], at(0, 15), "scheduled", "Please place bins outside the dean's office.");
  await schedule(OFFICES[1], at(0, 16, 30));
  await schedule(OFFICES[2], at(1, 9), "scheduled", "Separate shredded paper from other recyclables.");
  await schedule(OFFICES[3], at(1, 14));
  await schedule(OFFICES[4], at(2, 10), "scheduled", "Collector will check the pantry bins too.");
  await schedule(OFFICES[0], at(4, 8, 30));
  const cancelled = await schedule(OFFICES[3], at(3, 11));
  await cancelled.update({ status: "cancelled", statusNote: "Campus-wide holiday", cancelledAt: Timestamp.now() });

  console.log(`Seeded ${OFFICES.length} offices, ${assessed} assessed collections and 7 upcoming schedules.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => deleteApp(app));
