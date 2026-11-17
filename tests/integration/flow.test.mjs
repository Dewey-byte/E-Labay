// End-to-end workflow test against the Auth, Firestore, Storage and Functions
// emulators (real Cloud Functions code + real security rules). Run with:
//   npm run test:integration
import assert from "node:assert/strict";
import { after, before, test } from "node:test";

import { initializeApp as initAdmin } from "firebase-admin/app";
import { getAuth as getAdminAuth } from "firebase-admin/auth";
import { getFirestore as getAdminDb } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInWithEmailAndPassword } from "firebase/auth";
import {
  Timestamp,
  connectFirestoreEmulator,
  doc,
  getDoc,
  getFirestore,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";

const PROJECT = "demo-elabay";
const REGION = "asia-southeast1";

initAdmin({ projectId: PROJECT });
const adminAuth = getAdminAuth();
const adminDb = getAdminDb();
const clients = [];

function client(name) {
  const app = initializeApp({ projectId: PROJECT, apiKey: "demo-key", authDomain: `${PROJECT}.firebaseapp.com` }, name);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, "127.0.0.1", 8080);
  const fns = getFunctions(app, REGION);
  connectFunctionsEmulator(fns, "127.0.0.1", 5001);
  clients.push(app);
  return { auth, db, call: (fn, data) => httpsCallable(fns, fn)(data).then((r) => r.data) };
}

async function waitFor(fn, label, timeoutMs = 30000) {
  const start = Date.now();
  for (;;) {
    const value = await fn();
    if (value) return value;
    if (Date.now() - start > timeoutMs) throw new Error(`Timed out waiting for ${label}`);
    await new Promise((r) => setTimeout(r, 400));
  }
}

const notificationsOf = async (uid, type) =>
  (await adminDb.collection("notifications").where("recipientId", "==", uid).where("notificationType", "==", type).get()).docs;

const collector = client("collector");
const faculty = client("faculty");
const state = {};

before(async () => {
  const user = await adminAuth.createUser({ email: "collector@test.edu", password: "collector-pass", displayName: "Carla Collector" });
  await adminAuth.setCustomUserClaims(user.uid, { role: "collector", officeId: null });
  await adminDb.doc(`users/${user.uid}`).set({
    uid: user.uid, fullName: "Carla Collector", email: "collector@test.edu", role: "collector",
    officeId: null, profileImage: null, isActive: true, pushEnabled: true,
  });
  state.collectorUid = user.uid;
  await signInWithEmailAndPassword(collector.auth, "collector@test.edu", "collector-pass");
});

after(async () => {
  await Promise.all(clients.map((app) => deleteApp(app)));
});

test("collector provisions a faculty office account (role assigned server-side)", async () => {
  const res = await collector.call("provisionFacultyAccount", {
    office: { officeName: "College of Engineering", building: "Engineering Bldg", description: "Dean's office" },
    account: { fullName: "Engineering Office", email: "eng@test.edu", password: "faculty-pass" },
  });
  assert.ok(res.uid && res.officeId);
  state.officeId = res.officeId;
  state.facultyUid = res.uid;

  const record = await adminAuth.getUser(res.uid);
  assert.deepEqual(record.customClaims, { role: "faculty", officeId: res.officeId });
  const office = (await adminDb.doc(`offices/${res.officeId}`).get()).data();
  assert.equal(office.totalPoints, 0);
  assert.equal(office.officeName, "College of Engineering");

  await assert.rejects(
    collector.call("provisionFacultyAccount", {
      officeId: res.officeId,
      account: { fullName: "Dup", email: "eng@test.edu", password: "faculty-pass" },
    }),
    /already exists/i,
  );
});

test("faculty cannot provision accounts or submit assessments", async () => {
  await signInWithEmailAndPassword(faculty.auth, "eng@test.edu", "faculty-pass");
  await assert.rejects(
    faculty.call("provisionFacultyAccount", { office: { officeName: "X", building: "Y" }, account: { fullName: "a", email: "x@test.edu", password: "12345678" } }),
    /Collector/,
  );
  await assert.rejects(faculty.call("submitCollectionAssessment", { scheduleId: "nope", segregationResults: {} }), /Collector/);
});

test("collector creates a schedule; the office is notified", async () => {
  const ref = doc(collector.db, "schedules", "sched-1");
  await setDoc(ref, {
    scheduleId: "sched-1",
    officeId: state.officeId,
    officeName: "College of Engineering",
    building: "Engineering Bldg",
    collectorId: state.collectorUid,
    collectorName: "Carla Collector",
    collectionDate: Timestamp.fromMillis(Date.now() + 2 * 3600 * 1000),
    collectionTime: "10:00",
    notes: "Please bring bins to the hallway",
    status: "scheduled",
    reminderSent: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  const [n] = await waitFor(() => notificationsOf(state.facultyUid, "schedule_created").then((d) => d.length && d), "schedule notification");
  assert.equal(n.data().relatedId, "sched-1");
  assert.match(n.data().message, /bins to the hallway/);

  // Faculty sees its own schedule.
  const snap = await getDoc(doc(faculty.db, "schedules", "sched-1"));
  assert.equal(snap.data().status, "scheduled");
});

test("collector submits the assessment; points, records and leaderboard update atomically", async () => {
  await updateDoc(doc(collector.db, "schedules", "sched-1"), { status: "in_progress", updatedAt: serverTimestamp() });
  const res = await collector.call("submitCollectionAssessment", {
    scheduleId: "sched-1",
    segregationResults: {
      biodegradable: "proper",
      non_biodegradable: "proper",
      recyclable: "improper",
      residual: "not_applicable",
    },
    remarks: "Recyclables mixed with food waste",
    evidenceImageUrls: [],
  });
  assert.deepEqual(res, { collectionId: "sched-1", pointsAwarded: 20, maxPoints: 30 });

  const office = (await adminDb.doc(`offices/${state.officeId}`).get()).data();
  assert.equal(office.totalPoints, 20);
  assert.equal(office.totalCollections, 1);
  assert.equal(office.totalProperSegregations, 2);
  assert.equal(office.totalAssessments, 3);
  assert.deepEqual(office.categoryStats.recyclable, { proper: 0, improper: 1 });
  assert.deepEqual(office.categoryStats.residual, { proper: 0, improper: 0 });

  const schedule = (await adminDb.doc("schedules/sched-1").get()).data();
  assert.equal(schedule.status, "completed");
  assert.equal(schedule.pointsAwarded, 20);

  const tx = (await adminDb.doc("point_transactions/collection_sched-1").get()).data();
  assert.equal(tx.pointsAwarded, 20);
  assert.equal(tx.collectorId, state.collectorUid);
  assert.equal(tx.remarks, "Recyclables mixed with food waste");

  const collection = (await adminDb.doc("collections/sched-1").get()).data();
  assert.equal(collection.collectorName, "Carla Collector");
  assert.equal(collection.segregationResults.recyclable, "improper");

  assert.equal((await notificationsOf(state.facultyUid, "collection_completed")).length, 1);
  assert.equal((await notificationsOf(state.facultyUid, "points_awarded")).length, 1);

  // Faculty can read its own assessment.
  const own = await getDoc(doc(faculty.db, "collections", "sched-1"));
  assert.equal(own.data().pointsAwarded, 20);
});

test("duplicate submissions are rejected and never award points twice", async () => {
  await assert.rejects(
    collector.call("submitCollectionAssessment", {
      scheduleId: "sched-1",
      segregationResults: { biodegradable: "proper", non_biodegradable: "proper", recyclable: "proper", residual: "proper" },
    }),
    /already been assessed/,
  );
  const office = (await adminDb.doc(`offices/${state.officeId}`).get()).data();
  assert.equal(office.totalPoints, 20);
  const txs = await adminDb.collection("point_transactions").where("officeId", "==", state.officeId).get();
  assert.equal(txs.size, 1);
});

test("invalid assessments are rejected", async () => {
  await assert.rejects(
    collector.call("submitCollectionAssessment", { scheduleId: "sched-1", segregationResults: { biodegradable: "proper" } }),
    /invalid|Missing/i,
  );
});

test("reschedule and cancel notify the office", async () => {
  const ref = doc(collector.db, "schedules", "sched-2");
  const original = Timestamp.fromMillis(Date.now() + 72 * 3600 * 1000);
  await setDoc(ref, {
    scheduleId: "sched-2", officeId: state.officeId, officeName: "College of Engineering",
    collectorId: state.collectorUid, collectionDate: original, collectionTime: "08:00",
    notes: "", status: "scheduled", createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  await updateDoc(ref, {
    collectionDate: Timestamp.fromMillis(Date.now() + 96 * 3600 * 1000),
    collectionTime: "09:00",
    previousCollectionDate: original,
    status: "rescheduled",
    statusNote: "Campus event",
    reminderSent: false,
    updatedAt: serverTimestamp(),
  });
  const [r] = await waitFor(() => notificationsOf(state.facultyUid, "schedule_rescheduled").then((d) => d.length && d), "reschedule notification");
  assert.match(r.data().message, /Campus event/);

  await updateDoc(ref, { status: "cancelled", statusNote: "Holiday", cancelledAt: serverTimestamp(), updatedAt: serverTimestamp() });
  const [c] = await waitFor(() => notificationsOf(state.facultyUid, "schedule_cancelled").then((d) => d.length && d), "cancel notification");
  assert.match(c.data().message, /Holiday/);

  await assert.rejects(
    collector.call("submitCollectionAssessment", {
      scheduleId: "sched-2",
      segregationResults: { biodegradable: "proper", non_biodegradable: "proper", recyclable: "proper", residual: "proper" },
    }),
    /cancelled/,
  );
});

test("recalculating the leaderboard keeps totals consistent with the ledger", async () => {
  // Simulate drift, then repair it from the transaction ledger.
  await adminDb.doc(`offices/${state.officeId}`).update({ totalPoints: 999 });
  const res = await collector.call("recalculateLeaderboard");
  assert.equal(res.officesUpdated, 1);
  assert.equal(res.corrected, 1);
  const office = (await adminDb.doc(`offices/${state.officeId}`).get()).data();
  assert.equal(office.totalPoints, 20);
  assert.equal(office.totalAssessments, 3);
});

test("collector can deactivate a faculty account", async () => {
  await collector.call("setAccountStatus", { uid: state.facultyUid, isActive: false });
  const record = await adminAuth.getUser(state.facultyUid);
  assert.equal(record.disabled, true);
  const profile = (await adminDb.doc(`users/${state.facultyUid}`).get()).data();
  assert.equal(profile.isActive, false);
});
