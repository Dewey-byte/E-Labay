import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { COLLECTIONS, REGION, ROLE } from "./config";
import { auth, db } from "./firebase";
import { asInvalidArgument, requireCollector, requireId } from "./guards";
import { CATEGORIES, cleanString } from "./scoring";

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function emptyCategoryStats() {
  return Object.fromEntries(CATEGORIES.map((c) => [c, { proper: 0, improper: 0 }]));
}

/**
 * Collector-only account provisioning. Creates a Faculty Office login (and,
 * when no `officeId` is given, the office itself), assigns the `faculty` role
 * and office as custom claims, and writes the `users` profile. Users can never
 * choose their own role.
 *
 * Input: `{ officeId?, office?: {officeName, building, description}, account: {fullName, email, password} }`
 */
export const provisionFacultyAccount = onCall({ region: REGION }, async (request) => {
  const collector = await requireCollector(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const account = (data.account ?? {}) as Record<string, unknown>;

  const fullName = asInvalidArgument(() => cleanString(account.fullName, "Name", { max: 80, required: true }));
  const email = asInvalidArgument(() => cleanString(account.email, "Email", { max: 254, required: true })).toLowerCase();
  if (!EMAIL_PATTERN.test(email)) throw new HttpsError("invalid-argument", "Enter a valid email address.");
  const password = account.password;
  if (typeof password !== "string" || password.length < 8 || password.length > 128) {
    throw new HttpsError("invalid-argument", "The temporary password must be 8–128 characters.");
  }

  // Resolve or prepare the office.
  let officeId: string;
  let newOffice: Record<string, unknown> | null = null;
  if (data.officeId !== undefined && data.officeId !== null) {
    officeId = requireId(data.officeId, "officeId");
    const snap = await db.collection(COLLECTIONS.offices).doc(officeId).get();
    if (!snap.exists) throw new HttpsError("not-found", "That office does not exist.");
  } else {
    const office = (data.office ?? {}) as Record<string, unknown>;
    const officeName = asInvalidArgument(() => cleanString(office.officeName, "Office name", { max: 80, required: true }));
    const building = asInvalidArgument(() => cleanString(office.building, "Building", { max: 80, required: true }));
    const description = asInvalidArgument(() => cleanString(office.description, "Description", { max: 300, required: false }));
    const duplicate = await db.collection(COLLECTIONS.offices).where("officeName", "==", officeName).limit(1).get();
    if (!duplicate.empty) throw new HttpsError("already-exists", `An office named "${officeName}" already exists.`);
    officeId = db.collection(COLLECTIONS.offices).doc().id;
    newOffice = {
      officeId,
      officeName,
      building,
      description,
      totalPoints: 0,
      totalCollections: 0,
      totalProperSegregations: 0,
      totalAssessments: 0,
      categoryStats: emptyCategoryStats(),
      createdBy: collector.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
  }

  // Create the Auth user first so a duplicate email fails before any writes.
  let uid: string;
  try {
    const user = await auth.createUser({ email, password, displayName: fullName });
    uid = user.uid;
  } catch (e) {
    const code = (e as { code?: string }).code;
    if (code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "An account with this email already exists.");
    }
    if (code === "auth/invalid-password" || code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", (e as Error).message);
    }
    logger.error("createUser failed", e);
    throw new HttpsError("internal", "The account could not be created.");
  }

  try {
    await auth.setCustomUserClaims(uid, { role: ROLE.faculty, officeId });
    const batch = db.batch();
    if (newOffice) batch.set(db.collection(COLLECTIONS.offices).doc(officeId), newOffice);
    batch.set(db.collection(COLLECTIONS.users).doc(uid), {
      uid,
      fullName,
      email,
      role: ROLE.faculty,
      officeId,
      profileImage: null,
      isActive: true,
      pushEnabled: true,
      createdBy: collector.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
  } catch (e) {
    // Roll back the Auth user so a retry can succeed.
    await auth.deleteUser(uid).catch(() => undefined);
    logger.error("Provisioning failed; auth user rolled back", e);
    throw new HttpsError("internal", "The account could not be created. Please try again.");
  }

  logger.info("Faculty account provisioned", { uid, officeId, by: collector.uid });
  return { uid, officeId };
});

/**
 * Collector-only: activate or deactivate a Faculty Office account. A
 * deactivated account is disabled in Firebase Auth, its sessions are revoked
 * and its push tokens removed. Office records and points are kept.
 */
export const setAccountStatus = onCall({ region: REGION }, async (request) => {
  const collector = await requireCollector(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const uid = requireId(data.uid, "uid");
  if (typeof data.isActive !== "boolean") throw new HttpsError("invalid-argument", "isActive must be true or false.");
  const isActive = data.isActive;
  if (uid === collector.uid) throw new HttpsError("failed-precondition", "You cannot change your own account status.");

  const userRef = db.collection(COLLECTIONS.users).doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Account not found.");
  if (snap.data()?.role !== ROLE.faculty) {
    throw new HttpsError("permission-denied", "Only Faculty Office accounts can be managed here.");
  }

  await auth.updateUser(uid, { disabled: !isActive });
  if (!isActive) {
    await auth.revokeRefreshTokens(uid);
    const tokens = await userRef.collection(COLLECTIONS.fcmTokens).get();
    await Promise.all(tokens.docs.map((d) => d.ref.delete()));
  }
  await userRef.update({ isActive, updatedAt: FieldValue.serverTimestamp() });

  logger.info("Account status changed", { uid, isActive, by: collector.uid });
  return { uid, isActive };
});
