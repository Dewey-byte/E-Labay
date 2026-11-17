#!/usr/bin/env node
/**
 * Trusted administrative bootstrap for Collector accounts.
 *
 * Collectors cannot be created from the app. An administrator:
 *   1. creates the user in Firebase Console > Authentication > Add user
 *      (email + password), then
 *   2. runs this script with Application Default Credentials:
 *
 *      gcloud auth application-default login
 *      node scripts/create-collector.js --project <project-id> --email collector@school.edu --name "Juan Dela Cruz"
 *
 * It writes `users/{uid}` with role "collector" (security rules read roles
 * from there) and seeds `config/scoring` with the default point values if it
 * does not exist. Works on the free Spark plan. No service-account key is
 * stored in the repository or the app.
 */
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : undefined;
}

async function main() {
  const projectId = arg("project") ?? process.env.GCLOUD_PROJECT;
  const email = arg("email");
  const name = arg("name");
  if (!projectId || !email) {
    console.error('Usage: node scripts/create-collector.js --project <id> --email <email> [--name "Full Name"]');
    process.exit(1);
  }

  initializeApp({ credential: applicationDefault(), projectId });
  const auth = getAuth();
  const db = getFirestore();

  const user = await auth.getUserByEmail(email).catch(() => null);
  if (!user) {
    console.error(`No Firebase Auth user found for ${email}. Create it in the Firebase Console first.`);
    process.exit(1);
  }

  await db.collection("users").doc(user.uid).set(
    {
      uid: user.uid,
      fullName: name ?? user.displayName ?? email,
      email: user.email,
      role: "collector",
      officeId: null,
      profileImage: null,
      isActive: true,
      pushEnabled: true,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const scoringRef = db.collection("config").doc("scoring");
  if (!(await scoringRef.get()).exists) {
    await scoringRef.set({
      properPoints: 10,
      improperPoints: 0,
      updatedBy: user.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    console.log("Seeded config/scoring with the default point values (10 / 0).");
  }

  console.log(`${email} (${user.uid}) is now an E-Labay Collector. Sign in to the app with this account.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
