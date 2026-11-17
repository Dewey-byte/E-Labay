// Security-rules tests for E-Labay (Spark-plan rules). Run on the emulators:
//   npm run test:rules
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";

import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from "firebase/firestore";
import { getBytes, ref, uploadBytes } from "firebase/storage";

let env;
const HOUR = 3600 * 1000;
const inHours = (h) => Timestamp.fromMillis(Date.now() + h * HOUR);
const SA_DATE = inHours(20); // within the 24 h reminder window
const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);

const ctx = (uid) => env.authenticatedContext(uid);
const collector = () => ctx("collector1").firestore();
const facultyA = () => ctx("facA").firestore();
const facultyB = () => ctx("facB").firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

function newSchedule(overrides = {}) {
  return {
    scheduleId: "new1", officeId: "officeA", officeName: "Office A", building: "Main",
    collectorId: "collector1", collectorName: "Collector One", collectionDate: inHours(48),
    collectionTime: "09:30", notes: "Bins outside please", status: "scheduled", reminderSent: false,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides,
  };
}

function notification(id, overrides = {}) {
  return {
    notificationId: id, recipientId: "facA", recipientRole: "faculty", officeId: "officeA",
    title: "Hello", message: "A message", notificationType: "schedule_updated", relatedId: "sA",
    isRead: false, createdAt: serverTimestamp(), ...overrides,
  };
}

const RESULTS = { biodegradable: "proper", non_biodegradable: "improper", recyclable: "not_applicable", residual: "proper" };

// Builds the same atomic write the app's CollectionRepository.submitAssessment makes.
function assessmentBatch(db, { scheduleId = "sA", results = RESULTS, override = {} } = {}) {
  const proper = Object.values(results).filter((r) => r === "proper").length;
  const improper = Object.values(results).filter((r) => r === "improper").length;
  const points = proper * 10;
  const batch = writeBatch(db);
  const now = serverTimestamp();
  batch.set(doc(db, "collections", scheduleId), {
    collectionId: scheduleId, scheduleId, officeId: "officeA", officeName: "Office A",
    collectorId: "collector1", collectorName: "Collector One", segregationResults: results,
    properCount: proper, improperCount: improper, applicableCount: proper + improper,
    pointsAwarded: points, maxPoints: (proper + improper) * 10, scoring: { properPoints: 10, improperPoints: 0 },
    remarks: "Good job", evidenceImageUrls: [], scheduledDate: SA_DATE, collectedAt: now, createdAt: now,
    ...(override.collection ?? {}),
  });
  if (!override.skipTransaction) {
    batch.set(doc(db, "point_transactions", `collection_${scheduleId}`), {
      transactionId: `collection_${scheduleId}`, officeId: "officeA", officeName: "Office A",
      collectionId: scheduleId, scheduleId, pointsAwarded: points, transactionType: "collection_assessment",
      properCount: proper, applicableCount: proper + improper, remarks: "Good job",
      collectorId: "collector1", collectorName: "Collector One", assessmentDate: now, createdAt: now,
      ...(override.transaction ?? {}),
    });
  }
  const stat = (c) => ({ proper: results[c] === "proper" ? 1 : 0, improper: results[c] === "improper" ? 1 : 0 });
  if (!override.skipOffice) {
    batch.update(doc(db, "offices", "officeA"), {
      totalPoints: 30 + points, totalCollections: 2, totalProperSegregations: 3 + proper,
      totalAssessments: 4 + proper + improper,
      categoryStats: {
        biodegradable: stat("biodegradable"), non_biodegradable: stat("non_biodegradable"),
        recyclable: stat("recyclable"), residual: stat("residual"),
      },
      lastCollectionId: scheduleId, lastPointsAwarded: points, lastCollectionAt: now, updatedAt: now,
      ...(override.office ?? {}),
    });
  }
  if (!override.skipSchedule) {
    batch.update(doc(db, "schedules", scheduleId), {
      status: "completed", collectionId: scheduleId, pointsAwarded: points, completedAt: now, updatedAt: now,
    });
  }
  batch.set(doc(db, "notifications", `completed_${scheduleId}_facA`),
    notification(`completed_${scheduleId}_facA`, { notificationType: "collection_completed", relatedId: scheduleId }));
  return batch;
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-elabay",
    firestore: { rules: readFileSync("firestore.rules", "utf8") },
    storage: { rules: readFileSync("storage.rules", "utf8") },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const user = (role, officeId, name, isActive = true) => ({
      uid: name, fullName: name, email: `${name}@test.edu`, role, officeId, profileImage: null,
      isActive, pushEnabled: true, createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    });
    await setDoc(doc(db, "users/collector1"), user("collector", null, "collector1"));
    await setDoc(doc(db, "users/facA"), user("faculty", "officeA", "facA"));
    await setDoc(doc(db, "users/facB"), user("faculty", "officeB", "facB"));
    await setDoc(doc(db, "users/inactiveCollector"), user("collector", null, "inactiveCollector", false));
    for (const id of ["officeA", "officeB"]) {
      await setDoc(doc(db, `offices/${id}`), {
        officeId: id, officeName: id === "officeA" ? "Office A" : "Office B", building: "Main",
        description: "", totalPoints: id === "officeA" ? 30 : 10, totalCollections: 1,
        totalProperSegregations: 3, totalAssessments: 4, categoryStats: {},
      });
    }
    const schedule = (officeId, status, date = SA_DATE) => ({
      officeId, officeName: officeId, collectorId: "collector1", collectionDate: date,
      collectionTime: "08:00", notes: "", status, updatedAt: Timestamp.now(),
    });
    await setDoc(doc(db, "schedules/sA"), schedule("officeA", "in_progress"));
    await setDoc(doc(db, "schedules/sA2"), schedule("officeA", "scheduled"));
    await setDoc(doc(db, "schedules/sFar"), schedule("officeA", "scheduled", inHours(72)));
    await setDoc(doc(db, "schedules/sB"), schedule("officeB", "scheduled"));
    await setDoc(doc(db, "schedules/sDone"), schedule("officeA", "completed"));
    await setDoc(doc(db, "collections/cA"), { officeId: "officeA", pointsAwarded: 30 });
    await setDoc(doc(db, "collections/cB"), { officeId: "officeB", pointsAwarded: 10 });
    await setDoc(doc(db, "point_transactions/tA"), { officeId: "officeA", pointsAwarded: 30, createdAt: Timestamp.now() });
    await setDoc(doc(db, "point_transactions/tB"), { officeId: "officeB", pointsAwarded: 10, createdAt: Timestamp.now() });
    await setDoc(doc(db, "notifications/nA"), { recipientId: "facA", title: "Hi", message: "m", isRead: false, createdAt: Timestamp.now() });
    await setDoc(doc(db, "notifications/nB"), { recipientId: "facB", title: "Hi", message: "m", isRead: false, createdAt: Timestamp.now() });
    await setDoc(doc(db, "config/scoring"), { properPoints: 10, improperPoints: 0 });
  });
});

describe("1. authentication and profiles", () => {
  test("anonymous users cannot read anything", async () => {
    await assertFails(getDoc(doc(anonymous(), "offices/officeA")));
    await assertFails(getDoc(doc(anonymous(), "schedules/sA")));
    await assertFails(getDoc(doc(anonymous(), "config/scoring")));
  });
  test("signed-in users without a profile (self-registered) get nothing", async () => {
    const stranger = ctx("stranger").firestore();
    await assertFails(getDoc(doc(stranger, "offices/officeA")));
    await assertFails(setDoc(doc(stranger, "users/stranger"), { role: "collector", fullName: "x", isActive: true }));
  });
  test("deactivated accounts lose access", async () => {
    await assertFails(setDoc(doc(ctx("inactiveCollector").firestore(), "schedules/new1"), newSchedule({ collectorId: "inactiveCollector" })));
  });
});

describe("account provisioning by the Collector", () => {
  const office = () => ({
    officeId: "officeC", officeName: "Office C", building: "Annex", description: "", totalPoints: 0,
    totalCollections: 0, totalProperSegregations: 0, totalAssessments: 0, categoryStats: {},
    createdBy: "collector1", createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  const profile = (overrides = {}) => ({
    uid: "facC", fullName: "Office C", email: "c@test.edu", role: "faculty", officeId: "officeC",
    profileImage: null, isActive: true, pushEnabled: true, createdBy: "collector1",
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides,
  });
  test("collector creates an office and its faculty profile in one batch", async () => {
    const db = collector();
    const batch = writeBatch(db);
    batch.set(doc(db, "offices/officeC"), office());
    batch.set(doc(db, "users/facC"), profile());
    await assertSucceeds(batch.commit());
  });
  test("collector cannot create collector profiles or offices with points", async () => {
    await assertFails(setDoc(doc(collector(), "users/facC"), profile({ role: "collector", officeId: "officeA" })));
    await assertFails(setDoc(doc(collector(), "offices/officeC"), { ...office(), totalPoints: 500 }));
  });
  test("faculty cannot provision accounts", async () => {
    await assertFails(setDoc(doc(facultyA(), "users/facC"), profile({ officeId: "officeA", createdBy: "facA" })));
  });
  test("collector deactivates and reactivates a faculty account", async () => {
    await assertSucceeds(updateDoc(doc(collector(), "users/facA"), { isActive: false, updatedAt: serverTimestamp() }));
    await assertFails(getDoc(doc(facultyA(), "schedules/sA")));
    await assertFails(updateDoc(doc(collector(), "users/facA"), { role: "collector", updatedAt: serverTimestamp() }));
  });
});

describe("2. schedules: only Collectors create and manage", () => {
  test("collector can create a valid schedule with its notification", async () => {
    const db = collector();
    const batch = writeBatch(db);
    batch.set(doc(db, "schedules/new1"), newSchedule());
    batch.set(doc(db, "notifications/created_new1_facA"),
      notification("created_new1_facA", { notificationType: "schedule_created", relatedId: "new1" }));
    await assertSucceeds(batch.commit());
  });
  test("faculty cannot create schedules", async () => {
    await assertFails(setDoc(doc(facultyA(), "schedules/new1"), newSchedule({ collectorId: "facA" })));
  });
  test("invalid schedules are rejected", async () => {
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ status: "completed" })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ collectorId: "someoneElse" })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ officeName: "Fake" })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ officeId: "ghost" })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ collectionDate: inHours(-3) })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ collectionTime: "25:00" })));
  });
  test("cancel requires a reason; moving the date requires rescheduled", async () => {
    await assertFails(updateDoc(doc(collector(), "schedules/sA2"), { status: "cancelled", updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(collector(), "schedules/sA2"), {
      status: "cancelled", statusNote: "Holiday", cancelledAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(collector(), "schedules/sFar"), { collectionDate: inHours(96), updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(collector(), "schedules/sFar"), {
      collectionDate: inHours(96), collectionTime: "10:00", status: "rescheduled", statusNote: "Rain",
      previousCollectionDate: inHours(72), reminderSent: false, updatedAt: serverTimestamp(),
    }));
  });
  test("collector can start a collection", async () => {
    await assertSucceeds(updateDoc(doc(collector(), "schedules/sA2"), { status: "in_progress", updatedAt: serverTimestamp() }));
  });
  test("reminder: only within 24 hours, once", async () => {
    const reminder = { status: "upcoming", reminderSent: true, reminderSentAt: serverTimestamp(), updatedAt: serverTimestamp() };
    await assertFails(updateDoc(doc(collector(), "schedules/sFar"), reminder));
    await assertSucceeds(updateDoc(doc(collector(), "schedules/sA2"), reminder));
    await assertFails(updateDoc(doc(collector(), "schedules/sA2"), reminder));
  });
  test("clients cannot complete a schedule without an assessment", async () => {
    await assertFails(updateDoc(doc(collector(), "schedules/sA"), {
      status: "completed", collectionId: "sA", pointsAwarded: 40, completedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(collector(), "schedules/sA"), { pointsAwarded: 40, updatedAt: serverTimestamp() }));
  });
  test("completed schedules are immutable and schedules cannot be deleted", async () => {
    await assertFails(updateDoc(doc(collector(), "schedules/sDone"), { notes: "x", updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(collector(), "schedules/sA")));
  });
  test("faculty cannot edit, reschedule or cancel", async () => {
    await assertFails(updateDoc(doc(facultyA(), "schedules/sA2"), { status: "cancelled", statusNote: "no", updatedAt: serverTimestamp() }));
  });
});

describe("3/9. assessments: verified atomic write", () => {
  test("a correct assessment commits and awards the recomputed points", async () => {
    await assertSucceeds(assessmentBatch(collector()).commit());
    const office = await getDoc(doc(collector(), "offices/officeA"));
    if (office.data().totalPoints !== 50) throw new Error(`expected 50 points, got ${office.data().totalPoints}`);
  });
  test("duplicate submissions are rejected", async () => {
    await assertSucceeds(assessmentBatch(collector()).commit());
    await assertFails(assessmentBatch(collector()).commit());
  });
  test("forged points are rejected (collection, transaction or office)", async () => {
    await assertFails(assessmentBatch(collector(), { override: { collection: { pointsAwarded: 40 } } }).commit());
    await assertFails(assessmentBatch(collector(), { override: { transaction: { pointsAwarded: 40 } } }).commit());
    await assertFails(assessmentBatch(collector(), { override: { office: { totalPoints: 999 } } }).commit());
    await assertFails(assessmentBatch(collector(), { override: { office: { totalCollections: 5 } } }).commit());
    await assertFails(assessmentBatch(collector(), { override: { collection: { properCount: 4 } } }).commit());
    await assertFails(assessmentBatch(collector(), {
      override: { office: { categoryStats: { biodegradable: { proper: 9, improper: 0 } } } },
    }).commit());
  });
  test("scoring must match config/scoring", async () => {
    await assertFails(assessmentBatch(collector(), {
      override: { collection: { scoring: { properPoints: 20, improperPoints: 0 } } },
    }).commit());
  });
  test("partial writes are rejected", async () => {
    await assertFails(assessmentBatch(collector(), { override: { skipTransaction: true } }).commit());
    await assertFails(assessmentBatch(collector(), { override: { skipOffice: true } }).commit());
    await assertFails(assessmentBatch(collector(), { override: { skipSchedule: true } }).commit());
  });
  test("invalid segregation results are rejected", async () => {
    await assertFails(assessmentBatch(collector(), { results: { ...RESULTS, recyclable: "great" } }).commit());
  });
  test("cancelled or completed schedules cannot be assessed", async () => {
    await assertFails(assessmentBatch(collector(), { scheduleId: "sDone" }).commit());
  });
  test("faculty cannot submit assessments", async () => {
    await assertFails(assessmentBatch(facultyA()).commit());
  });
  test("standalone ledger or office-total writes are rejected", async () => {
    await assertFails(setDoc(doc(collector(), "point_transactions/collection_sA2"), {
      transactionId: "collection_sA2", officeId: "officeA", collectionId: "sA2", pointsAwarded: 40,
    }));
    await assertFails(updateDoc(doc(collector(), "offices/officeA"), {
      totalPoints: 100, lastCollectionId: "cA", updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(collector(), "collections/cA"), { pointsAwarded: 40 }));
  });
});

describe("4/8. faculty see only their own private records", () => {
  test("own schedules, collections and transactions are readable", async () => {
    await assertSucceeds(getDoc(doc(facultyA(), "schedules/sA")));
    await assertSucceeds(getDoc(doc(facultyA(), "collections/cA")));
    await assertSucceeds(getDoc(doc(facultyA(), "point_transactions/tA")));
    await assertSucceeds(getDocs(query(collection(facultyA(), "schedules"), where("officeId", "==", "officeA"))));
    await assertSucceeds(getDocs(query(
      collection(facultyA(), "point_transactions"), where("officeId", "==", "officeA"), orderBy("createdAt", "desc"),
    )));
  });
  test("another office's records are not readable", async () => {
    await assertFails(getDoc(doc(facultyA(), "schedules/sB")));
    await assertFails(getDoc(doc(facultyA(), "collections/cB")));
    await assertFails(getDoc(doc(facultyA(), "point_transactions/tB")));
    await assertFails(getDocs(query(collection(facultyA(), "schedules"), where("officeId", "==", "officeB"))));
    await assertFails(getDocs(collection(facultyA(), "schedules")));
  });
  test("faculty cannot read other users' profiles; collector can", async () => {
    await assertFails(getDoc(doc(facultyA(), "users/facB")));
    await assertSucceeds(getDoc(doc(facultyA(), "users/facA")));
    await assertSucceeds(getDoc(doc(collector(), "users/facB")));
    await assertFails(getDocs(collection(facultyA(), "users")));
  });
});

describe("5. faculty cannot modify points", () => {
  test("office counters cannot be changed directly", async () => {
    await assertFails(updateDoc(doc(facultyA(), "offices/officeA"), { totalPoints: 9999 }));
    await assertFails(updateDoc(doc(collector(), "offices/officeA"), { totalPoints: 9999, updatedAt: serverTimestamp() }));
  });
  test("collector can edit descriptive office fields", async () => {
    await assertSucceeds(updateDoc(doc(collector(), "offices/officeA"), {
      officeName: "Office A (Renamed)", building: "Annex", description: "2nd floor", updatedAt: serverTimestamp(),
    }));
  });
});

describe("6. leaderboard is visible to all faculty", () => {
  test("faculty can list all offices ordered by points", async () => {
    const snap = await assertSucceeds(getDocs(query(collection(facultyB(), "offices"), orderBy("totalPoints", "desc"))));
    if (snap.size !== 2) throw new Error(`expected 2 offices, got ${snap.size}`);
  });
});

describe("7. users cannot change their role", () => {
  test("role, officeId and isActive are immutable for the user", async () => {
    await assertFails(updateDoc(doc(facultyA(), "users/facA"), { role: "collector", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(facultyA(), "users/facA"), { officeId: "officeB", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(facultyA(), "users/facA"), { isActive: false, updatedAt: serverTimestamp() }));
  });
  test("user can edit own name and push preference", async () => {
    await assertSucceeds(updateDoc(doc(facultyA(), "users/facA"), { fullName: "New Name", updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(facultyA(), "users/facA"), { pushEnabled: false, updatedAt: serverTimestamp() }));
  });
  test("users manage only their own FCM tokens", async () => {
    const token = { token: "tok123", platform: "android", createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(facultyA(), "users/facA/fcmTokens/tok123"), token));
    await assertFails(setDoc(doc(facultyA(), "users/facB/fcmTokens/tok123"), token));
  });
});

describe("notifications", () => {
  test("recipient can read and mark own notification as read", async () => {
    await assertSucceeds(getDoc(doc(facultyA(), "notifications/nA")));
    await assertSucceeds(getDocs(query(
      collection(facultyA(), "notifications"), where("recipientId", "==", "facA"), orderBy("createdAt", "desc"),
    )));
    await assertSucceeds(updateDoc(doc(facultyA(), "notifications/nA"), { isRead: true, readAt: serverTimestamp() }));
  });
  test("collector notifies only accounts of the schedule's office", async () => {
    await assertSucceeds(setDoc(doc(collector(), "notifications/updated_sA_1_facA"), notification("updated_sA_1_facA")));
    await assertFails(setDoc(doc(collector(), "notifications/x_facB"), notification("x_facB", { recipientId: "facB" })));
    await assertFails(setDoc(doc(collector(), "notifications/y_facA"), notification("y_facA", { relatedId: "sB" })));
  });
  test("faculty cannot create, edit or delete notifications", async () => {
    await assertFails(getDoc(doc(facultyA(), "notifications/nB")));
    await assertFails(updateDoc(doc(facultyA(), "notifications/nA"), { title: "Hacked" }));
    await assertFails(setDoc(doc(facultyA(), "notifications/fake"), notification("fake")));
    await assertFails(deleteDoc(doc(facultyA(), "notifications/nA")));
  });
});

describe("scoring configuration", () => {
  test("collector can update valid scoring values", async () => {
    await assertSucceeds(setDoc(doc(collector(), "config/scoring"), {
      properPoints: 15, improperPoints: 5, updatedBy: "collector1", updatedAt: serverTimestamp(),
    }));
  });
  test("invalid values and faculty edits are rejected", async () => {
    await assertFails(setDoc(doc(collector(), "config/scoring"), {
      properPoints: 5, improperPoints: 10, updatedBy: "collector1", updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(facultyA(), "config/scoring"), {
      properPoints: 100, improperPoints: 100, updatedBy: "facA", updatedAt: serverTimestamp(),
    }));
  });
});

describe("storage (Blaze only): collection evidence", () => {
  test("collectors upload images; faculty cannot", async () => {
    const c = ctx("collector1").storage();
    await assertSucceeds(uploadBytes(ref(c, "collections/officeA/sA/1.png"), png, { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(c, "collections/officeA/sA/2.txt"), png, { contentType: "text/plain" }));
    await assertFails(uploadBytes(ref(ctx("facA").storage(), "collections/officeA/sA/3.png"), png, { contentType: "image/png" }));
  });
  test("only the owning office (and collectors) can read evidence", async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await uploadBytes(ref(c.storage(), "collections/officeA/sA/seed.png"), png, { contentType: "image/png" });
    });
    await assertSucceeds(getBytes(ref(ctx("facA").storage(), "collections/officeA/sA/seed.png")));
    await assertFails(getBytes(ref(ctx("facB").storage(), "collections/officeA/sA/seed.png")));
  });
});
