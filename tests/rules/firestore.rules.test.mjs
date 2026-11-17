// Security-rules tests for E-Labay. Run on the emulators with:
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
} from "firebase/firestore";
import { getBytes, ref, uploadBytes } from "firebase/storage";

let env;
const tomorrow = () => Timestamp.fromMillis(Date.now() + 24 * 3600 * 1000);
const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);

const collector = () => env.authenticatedContext("collector1", { role: "collector" }).firestore();
const facultyA = () => env.authenticatedContext("facA", { role: "faculty", officeId: "officeA" }).firestore();
const facultyB = () => env.authenticatedContext("facB", { role: "faculty", officeId: "officeB" }).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

function newSchedule(overrides = {}) {
  return {
    scheduleId: "new1",
    officeId: "officeA",
    officeName: "Office A",
    building: "Main",
    collectorId: "collector1",
    collectorName: "Collector One",
    collectionDate: tomorrow(),
    collectionTime: "09:30",
    notes: "Bins outside please",
    status: "scheduled",
    reminderSent: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
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
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const user = (role, officeId, name) => ({
      fullName: name, email: `${name}@test.edu`, role, officeId, profileImage: null,
      isActive: true, pushEnabled: true, createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    });
    await setDoc(doc(db, "users/collector1"), user("collector", null, "collector"));
    await setDoc(doc(db, "users/facA"), user("faculty", "officeA", "facA"));
    await setDoc(doc(db, "users/facB"), user("faculty", "officeB", "facB"));
    for (const id of ["officeA", "officeB"]) {
      await setDoc(doc(db, `offices/${id}`), {
        officeId: id, officeName: id === "officeA" ? "Office A" : "Office B", building: "Main",
        description: "", totalPoints: id === "officeA" ? 30 : 10, totalCollections: 1,
        totalProperSegregations: 3, totalAssessments: 4, categoryStats: {},
      });
    }
    const schedule = (officeId, status) => ({
      officeId, officeName: officeId, collectorId: "collector1", collectionDate: tomorrow(),
      collectionTime: "08:00", notes: "", status, updatedAt: Timestamp.now(),
    });
    await setDoc(doc(db, "schedules/sA"), schedule("officeA", "scheduled"));
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

describe("1. authentication required", () => {
  test("anonymous users cannot read anything", async () => {
    await assertFails(getDoc(doc(anonymous(), "offices/officeA")));
    await assertFails(getDoc(doc(anonymous(), "schedules/sA")));
    await assertFails(getDoc(doc(anonymous(), "config/scoring")));
  });
});

describe("2. schedules: only Collectors create and manage", () => {
  test("collector can create a valid schedule", async () => {
    await assertSucceeds(setDoc(doc(collector(), "schedules/new1"), newSchedule()));
  });
  test("faculty cannot create schedules", async () => {
    const db = env.authenticatedContext("facA", { role: "faculty", officeId: "officeA" }).firestore();
    await assertFails(setDoc(doc(db, "schedules/new1"), newSchedule({ collectorId: "facA" })));
  });
  test("collector cannot create a schedule that is already completed or for another collector", async () => {
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ status: "completed" })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ collectorId: "someoneElse" })));
  });
  test("office name must match the office and the office must exist", async () => {
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ officeName: "Fake" })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ officeId: "ghost" })));
  });
  test("schedule cannot be created in the past or with a bad time", async () => {
    const past = Timestamp.fromMillis(Date.now() - 3 * 3600 * 1000);
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ collectionDate: past })));
    await assertFails(setDoc(doc(collector(), "schedules/new1"), newSchedule({ collectionTime: "25:00" })));
  });
  test("collector can cancel with a reason, not without", async () => {
    await assertFails(updateDoc(doc(collector(), "schedules/sA"), { status: "cancelled", updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(collector(), "schedules/sA"), {
      status: "cancelled", statusNote: "Holiday", cancelledAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });
  test("moving the date requires status rescheduled", async () => {
    const newDate = Timestamp.fromMillis(Date.now() + 48 * 3600 * 1000);
    await assertFails(updateDoc(doc(collector(), "schedules/sA"), { collectionDate: newDate, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(collector(), "schedules/sA"), {
      collectionDate: newDate, collectionTime: "10:00", status: "rescheduled", statusNote: "Rain",
      previousCollectionDate: Timestamp.now(), reminderSent: false, updatedAt: serverTimestamp(),
    }));
  });
  test("collector can start a collection (in progress)", async () => {
    await assertSucceeds(updateDoc(doc(collector(), "schedules/sA"), { status: "in_progress", updatedAt: serverTimestamp() }));
  });
  test("clients can never mark a schedule completed or upcoming", async () => {
    await assertFails(updateDoc(doc(collector(), "schedules/sA"), { status: "completed", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(collector(), "schedules/sA"), { status: "upcoming", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(collector(), "schedules/sA"), { pointsAwarded: 40, updatedAt: serverTimestamp() }));
  });
  test("completed schedules are immutable and schedules cannot be deleted", async () => {
    await assertFails(updateDoc(doc(collector(), "schedules/sDone"), { notes: "x", updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(collector(), "schedules/sA")));
  });
  test("faculty cannot edit, reschedule or cancel", async () => {
    await assertFails(updateDoc(doc(facultyA(), "schedules/sA"), {
      status: "cancelled", statusNote: "no", updatedAt: serverTimestamp(),
    }));
  });
});

describe("3/9. assessments and points are backend-only", () => {
  test("no client (even a collector) can write collections or point transactions", async () => {
    await assertFails(setDoc(doc(collector(), "collections/x"), { officeId: "officeA", pointsAwarded: 40 }));
    await assertFails(setDoc(doc(collector(), "point_transactions/x"), { officeId: "officeA", pointsAwarded: 40 }));
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
    await assertFails(getDocs(collection(facultyA(), "collections")));
  });
  test("faculty cannot read other users' profiles; collector can", async () => {
    await assertFails(getDoc(doc(facultyA(), "users/facB")));
    await assertSucceeds(getDoc(doc(facultyA(), "users/facA")));
    await assertSucceeds(getDoc(doc(collector(), "users/facB")));
    await assertFails(getDocs(collection(facultyA(), "users")));
  });
});

describe("5. faculty cannot modify points", () => {
  test("office counters cannot be changed by any client", async () => {
    await assertFails(updateDoc(doc(facultyA(), "offices/officeA"), { totalPoints: 9999 }));
    await assertFails(updateDoc(doc(collector(), "offices/officeA"), { totalPoints: 9999, updatedAt: serverTimestamp() }));
  });
  test("collector can edit descriptive office fields", async () => {
    await assertSucceeds(updateDoc(doc(collector(), "offices/officeA"), {
      officeName: "Office A (Renamed)", building: "Annex", description: "2nd floor", updatedAt: serverTimestamp(),
    }));
  });
  test("faculty cannot create offices", async () => {
    await assertFails(setDoc(doc(facultyA(), "offices/new"), { officeName: "X", totalPoints: 1000 }));
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
  test("users cannot create their own profile", async () => {
    const db = env.authenticatedContext("newbie", {}).firestore();
    await assertFails(setDoc(doc(db, "users/newbie"), { role: "collector", fullName: "x" }));
  });
  test("users manage only their own FCM tokens", async () => {
    const token = { token: "tok123", platform: "android", createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(facultyA(), "users/facA/fcmTokens/tok123"), token));
    await assertFails(setDoc(doc(facultyA(), "users/facB/fcmTokens/tok123"), token));
    await assertFails(setDoc(doc(facultyA(), "users/facA/fcmTokens/other"), token));
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
  test("cannot read others' notifications, edit content, create or delete", async () => {
    await assertFails(getDoc(doc(facultyA(), "notifications/nB")));
    await assertFails(updateDoc(doc(facultyA(), "notifications/nA"), { title: "Hacked" }));
    await assertFails(setDoc(doc(facultyA(), "notifications/fake"), { recipientId: "facA", title: "x" }));
    await assertFails(setDoc(doc(collector(), "notifications/fake"), { recipientId: "facA", title: "x" }));
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
    await assertFails(setDoc(doc(collector(), "config/scoring"), {
      properPoints: 500, improperPoints: 0, updatedBy: "collector1", updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(facultyA(), "config/scoring"), {
      properPoints: 100, improperPoints: 100, updatedBy: "facA", updatedAt: serverTimestamp(),
    }));
  });
});

describe("storage: collection evidence", () => {
  test("collectors upload images; faculty cannot", async () => {
    const c = env.authenticatedContext("collector1", { role: "collector" }).storage();
    await assertSucceeds(uploadBytes(ref(c, "collections/officeA/sA/1.png"), png, { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(c, "collections/officeA/sA/2.txt"), png, { contentType: "text/plain" }));
    const f = env.authenticatedContext("facA", { role: "faculty", officeId: "officeA" }).storage();
    await assertFails(uploadBytes(ref(f, "collections/officeA/sA/3.png"), png, { contentType: "image/png" }));
  });
  test("only the owning office (and collectors) can read evidence", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), "collections/officeA/sA/seed.png"), png, { contentType: "image/png" });
    });
    const a = env.authenticatedContext("facA", { role: "faculty", officeId: "officeA" }).storage();
    const b = env.authenticatedContext("facB", { role: "faculty", officeId: "officeB" }).storage();
    await assertSucceeds(getBytes(ref(a, "collections/officeA/sA/seed.png")));
    await assertFails(getBytes(ref(b, "collections/officeA/sA/seed.png")));
  });
});
