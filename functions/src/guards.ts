import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { COLLECTIONS, ROLE } from "./config";
import { db } from "./firebase";
import { ValidationError } from "./scoring";

export interface CollectorContext {
  uid: string;
  name: string;
}

/**
 * Verifies the caller is an active Collector. Checks both the custom auth
 * claim and the `users` document so a revoked or deactivated account cannot
 * act even with a still-valid ID token.
 */
export async function requireCollector(request: CallableRequest): Promise<CollectorContext> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Please sign in to continue.");
  }
  if (request.auth.token.role !== ROLE.collector) {
    throw new HttpsError("permission-denied", "Only the Collector can perform this action.");
  }
  const snap = await db.collection(COLLECTIONS.users).doc(request.auth.uid).get();
  const data = snap.data();
  if (!snap.exists || data?.role !== ROLE.collector || data?.isActive === false) {
    throw new HttpsError("permission-denied", "Your Collector account is not active.");
  }
  const name = typeof data.fullName === "string" && data.fullName ? data.fullName : request.auth.token.email ?? "Collector";
  return { uid: request.auth.uid, name };
}

/** Converts validation failures into `invalid-argument` errors for the client. */
export function asInvalidArgument<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof ValidationError) throw new HttpsError("invalid-argument", e.message);
    throw e;
  }
}

export function requireId(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 128 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}
