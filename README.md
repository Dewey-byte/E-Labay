# E-Labay

**Online campus waste management and collection tracking.** E-Labay is a Flutter + Firebase mobile app for faculty offices on a school campus. A **Collector** manually schedules garbage collections, assesses each office's waste segregation at pickup, and awards points. **Faculty Offices** receive real-time schedules and notifications, track their points and performance, and compete on a campus-wide leaderboard.

<p align="center">
  <img src="docs/screenshots/login.png" alt="E-Labay sign-in screen" width="260">
  &nbsp;&nbsp;
  <img src="docs/screenshots/collector-dashboard.png" alt="Collector dashboard with today's collections and statistics" width="260">
</p>

| Layer | Technology |
|---|---|
| Mobile app | Flutter 3.47 · Dart 3.13 · Riverpod 3 · GoRouter 18 · fl_chart |
| Authentication | Firebase Authentication (email/password; role stored as a custom claim) |
| Database | Cloud Firestore (real-time listeners, server timestamps, composite indexes) |
| Trusted backend | Cloud Functions for Firebase v2 (TypeScript, Node 22) |
| Push notifications | Firebase Cloud Messaging |
| Evidence photos | Cloud Storage for Firebase |

## Contents

- [Features](#features)
- [How it works](#how-it-works)
- [Architecture](#architecture)
- [Run it locally (no Firebase project needed)](#run-it-locally-no-firebase-project-needed)
- [Deploy to your Firebase project](#deploy-to-your-firebase-project)
- [Testing](#testing)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Design notes](#design-notes)

---

## Features

E-Labay has two roles. Each user sees only their role's screens and bottom navigation.

### Collector

| Screen | What it does |
|---|---|
| Dashboard | Today's collections, faculty offices, total/pending/completed schedules, 7-day collection chart, status chart, upcoming collections, recent activity |
| Faculty offices | Search, filter by building, sort by points or segregation rate |
| Office details | Points, rank, performance charts, login accounts (create, deactivate), collection history |
| Add / edit office | Registers an office **and its login account** in one step |
| Schedules | Upcoming, by date or past; filter by office and status |
| Create / edit schedule | Office, date, time and optional instructions. Schedules are always created manually |
| Collection details | Start the collection, reschedule (with reason), cancel (with reason) |
| Assessment | Biodegradable, non-biodegradable, recyclable and residual waste, each marked *Proper*, *Improper* or *N/A*; remarks; up to 3 photos; live score; review before submitting |
| Submission confirmation | Points awarded and the per-category result |
| Collection history | Completed and cancelled collections; filter by office, date range and status |
| Assessment details | Results, points, remarks, photos and the Collector responsible |
| Profile / Settings | Name, photo, password; scoring rules; leaderboard recalculation |

### Faculty Office

| Screen | What it does |
|---|---|
| Dashboard | Office points, leaderboard rank, latest points, next collection, segregation performance, recent collections |
| Notifications | Real-time feed with unread badge, unread filter and "mark all read" |
| Notification details | Full message; opening it marks it read; links to the schedule or assessment |
| Collection schedule | The office's own upcoming and past collections (view only) |
| Collection / assessment details | Instructions, status updates, results and points |
| Leaderboard | Top-three podium, full ranking, own office highlighted |
| Points history | Every point transaction with date, Collector and remarks |
| Performance | Completed collections, total points, average score, proper segregation rate, trend and per-category charts |
| Profile / Settings | Name, photo, password; push notification toggle |

There is no point redemption and no automatic or recurring scheduling.

## How it works

1. **Login.** Firebase Auth signs the user in. The app reads the role and opens the Collector or Faculty dashboard.
2. **Schedule.** The Collector picks an office, date and time, adds optional instructions, and saves.
3. **Notify.** A Cloud Function writes a notification for the office and sends it as a push notification. Within 24 hours of the pickup the office is reminded and the schedule becomes *Upcoming*.
4. **Collect.** At the office, the Collector opens the schedule and taps *Start collection & assess* (*In Progress*).
5. **Assess.** The Collector rates the four waste categories, adds remarks and optional photos.
6. **Score.** The app previews the points; the Collector reviews and submits.
7. **Record.** In one database transaction, the server saves the collection, the point transaction and the office totals, then marks the schedule *Completed*. The leaderboard re-ranks immediately.
8. **Result.** The office is notified of the completed collection and the points earned.
9. **Monitor.** The office follows its points history, performance charts and leaderboard position.

## Architecture

```
Flutter app ── Riverpod providers ── repositories ──┬─ Firestore (real-time reads; Collector schedule writes)
                                                    ├─ Cloud Functions (provisioning, assessment, maintenance)
                                                    ├─ Storage (evidence and profile photos)
                                                    └─ FCM (device token registration)

Cloud Functions
  submitCollectionAssessment  one transaction: collection + point transaction + office totals
                              + schedule "completed" + office notifications
  onScheduleCreated/Updated   notify the office of new, rescheduled, cancelled or changed schedules
  onNotificationCreated       push each notification to the recipient's devices
  sendCollectionReminders     every 30 min: reminder + "upcoming" for pickups within 24 h
  provisionFacultyAccount     create office login accounts (role set server-side)
  setAccountStatus            deactivate / reactivate office accounts
  recalculateLeaderboard      rebuild office totals from the point ledger
```

### Project structure

```
lib/
  main.dart, app.dart, firebase_options.dart
  core/          constants, theme, utils (scoring, ranking, formatting, validation),
                 services (Firebase, push notifications, emulator mode), exceptions
  models/        user, office, schedule, collection, notification, point transaction, scoring config
  repositories/  Firestore, Functions and Storage access, one per area
  providers/     Riverpod state: session/auth, offices, schedules, collections, notifications,
                 leaderboard, points
  features/      authentication, collector, scheduling, assessment, collections, faculty,
                 notifications, leaderboard, points, profile
  shared/        reusable widgets (cards, chips, empty/error/loading states, paged list, dialogs)
                 and components (tiles, charts, performance section)
  routes/        app_routes.dart, app_router.dart (role-based redirects, bottom-navigation shells)
functions/       Cloud Functions (TypeScript), unit tests, create-collector admin script
tests/           security-rules tests, end-to-end emulator tests, demo data seed
test/            Dart unit, widget and screen-render tests
firestore.rules · firestore.indexes.json · storage.rules · firebase.json
```

### Data model

| Collection | Written by | Contents |
|---|---|---|
| `users/{uid}` | Functions / admin script. Users may edit only `fullName`, `profileImage`, `pushEnabled` | `role` (`collector` or `faculty`), `officeId` (null for Collectors), `isActive`. Device tokens in `fcmTokens/{token}` |
| `offices/{officeId}` | Functions (points and counters); Collector (name, building, description) | `totalPoints`, `totalCollections`, `totalProperSegregations`, `totalAssessments`, `categoryStats`. Also the leaderboard source |
| `schedules/{scheduleId}` | Collector (create, edit, reschedule, cancel, start); Functions (`upcoming`, `completed`) | `collectionDate` (date and time), `collectionTime` (`HH:mm`), `status`, `notes`, `statusNote` |
| `collections/{scheduleId}` | Functions only | `segregationResults`, `pointsAwarded`, `remarks`, `evidenceImageUrls`, Collector. Same id as the schedule, so a collection can be assessed only once |
| `point_transactions/collection_{scheduleId}` | Functions only | Permanent point ledger. The fixed id prevents double awards |
| `notifications/{id}` | Functions only; the recipient may only mark it read | `recipientId`, `title`, `message`, `notificationType`, `relatedId`, `isRead`, `createdAt` |
| `config/scoring` | Collector (validated by rules) | `properPoints` (default 10), `improperPoints` (default 0) |

### Points and leaderboard

For each collection, every **properly segregated** category earns 10 points, **improperly segregated** earns 0, and **not applicable** categories are left out. With the defaults a collection is worth at most 40 points. The Collector can change both values in Settings; changes apply to future assessments only.

The app shows the score before submission, but the Cloud Function recalculates it from the current scoring rules and is the only thing that awards points. The leaderboard ranks offices by total points. **Offices with equal points share a rank** (1, 2, 2, 4) and are listed alphabetically.

### Security

- Roles are **custom auth claims** set only by Cloud Functions or the admin script. Nobody can choose or change their own role. The app also signs out accounts that have no profile, an unknown role, or are deactivated.
- **Firestore rules** allow only signed-in users. Only Collectors can create or manage schedules, with field validation and allowed status changes. Only the server can complete a schedule, write collections or point transactions, create notifications, or change points. Faculty Offices can read only their own schedules, collections and point history. Every signed-in user can read the leaderboard (office totals).
- **Storage rules** let only Collectors upload evidence photos (images under 5 MB). Only Collectors and the office concerned can view them, and they cannot be changed afterwards.
- Every callable Cloud Function checks that the caller is an active Collector and validates its input.
- No service-account key is stored in the app or the repository. `firebase_options.dart` contains only public client identifiers.

---

## Run it locally (no Firebase project needed)

The Firebase Emulator Suite runs Auth, Firestore, Storage and the real Cloud Functions on your computer.

**You need:** Flutter 3.47+, Node.js 22 (20 also works), Java 21 on your `PATH`, and an Android emulator or device.

Install the tooling:

```bash
npm install
```

```bash
npm --prefix functions install
```

Start the emulators (this also builds the functions):

```bash
npm run emulators
```

In a second terminal, load demo data: 5 offices, two weeks of assessed collections and upcoming schedules.

```bash
npm run seed
```

Run the app against the emulators:

```bash
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

On a physical phone, also pass `--dart-define=FIREBASE_EMULATOR_HOST=<your computer's LAN IP>`.

**Demo sign-ins** (local emulators only):

| Role | Email | Password |
|---|---|---|
| Collector | `collector@elabay.test` | `collector123` |
| Faculty Office | `eng@elabay.test`, `educ@elabay.test`, `registrar@elabay.test`, `nursing@elabay.test`, `accounting@elabay.test` | `office123` |

The Emulator UI is at http://127.0.0.1:4000. Push notifications are not emulated, but the in-app notification feed works. Emulator data is cleared when the emulators stop; run `npm run seed` again after restarting.

## Deploy to your Firebase project

### 1. Create the Firebase project

In the [Firebase Console](https://console.firebase.google.com):

1. Create a project and upgrade it to the **Blaze** plan (required for Cloud Functions).
2. **Authentication → Sign-in method:** enable **Email/Password**.
3. **Firestore Database:** create it in **production mode** (for example in `asia-southeast1`).
4. **Storage:** click **Get started**.
5. **iOS push only:** upload an APNs authentication key under *Project settings → Cloud Messaging*. In Xcode, enable **Push Notifications** and **Background Modes → Remote notifications** for the Runner target. Android needs no extra setup.

### 2. Connect the tooling

```bash
npm install
```

```bash
npm --prefix functions install
```

```bash
npx firebase login
```

```bash
npx firebase use --add
```

### 3. Configure the Flutter app

```bash
dart pub global activate flutterfire_cli
```

```bash
flutterfire configure --platforms=android,ios
```

This replaces the placeholder `lib/firebase_options.dart` and adds `google-services.json` and `GoogleService-Info.plist`. Until then, the app opens on a "Firebase setup required" screen.

### 4. Deploy the backend

```bash
npx firebase deploy --only firestore,storage,functions
```

This deploys the security rules, indexes and Cloud Functions. Indexes take a few minutes to build.

### 5. Create the first Collector

Collector accounts cannot be created from the app.

1. In the Firebase Console, open **Authentication → Add user** and create the Collector's email and password.
2. Give that account the Collector role:

```bash
gcloud auth application-default login
```

```bash
npm --prefix functions run create-collector -- --project YOUR_PROJECT_ID --email collector@school.edu --name "Collector Name"
```

The script sets the Collector role, creates the user profile and saves the default scoring rules.

### 6. Run the app

```bash
flutter run
```

Sign in as the Collector and use **Offices → Add office** to register each faculty office with its login account. Give each office its temporary password privately; they can change it under **Profile**.

---

## Testing

| Suite | Command | Tests | Covers |
|---|---|---|---|
| Dart unit, widget and screen-render | `flutter test` | 35 | Scoring, leaderboard ties, role redirects, data parsing, shared widgets; main screens rendered on small and large phones |
| Cloud Functions unit | `npm --prefix functions test` | 8 | Scoring, scoring config, assessment and input validation |
| Security rules | `npm run test:rules` | 30 | All 10 access rules plus notifications, device tokens, scoring config and Storage |
| End-to-end | `npm run test:integration` | 9 | Account creation → schedule → notification → assessment → points and leaderboard → duplicate blocked → reschedule and cancel → recalculation → deactivation |

`npm test` runs the functions, rules and end-to-end suites. The rules and end-to-end tests start the emulators themselves and need Java 21. Run `flutter analyze` for static analysis.

## Configuration

| Setting | Where | Default |
|---|---|---|
| Cloud Functions region | `REGION` in `functions/src/config.ts` **and** `AppConstants.functionsRegion` in `lib/core/constants/app_constants.dart` | `asia-southeast1` |
| Time zone used in notification messages | `CAMPUS_TIME_ZONE` parameter (prompted on first deploy, or set in `functions/.env`) | `Asia/Manila` |
| Points per category | App: Collector → Profile → Settings → Scoring rules | 10 proper / 0 improper |
| Reminder window | `REMINDER_WINDOW_HOURS` in `functions/src/config.ts` | 24 hours |
| Evidence photos per collection | `MAX_EVIDENCE_PHOTOS` (functions) and `AppConstants.maxEvidencePhotos` (app) | 3 |
| Local emulator mode | `--dart-define=USE_FIREBASE_EMULATORS=true` (and optionally `FIREBASE_EMULATOR_HOST`) | off |

## Troubleshooting

| Problem | Fix |
|---|---|
| App shows "Firebase setup required" | Run `flutterfire configure`, or use the local emulator mode |
| "A required database index is still being built" | Wait a few minutes after `firebase deploy`, or redeploy `firestore.indexes.json` |
| A signed-in user sees "You do not have access" everywhere | The account has no role claim. Create Collectors with `create-collector` and offices from the app, not directly in the console |
| Emulators or Gradle fail with `Unable to establish loopback connection` (Windows) | Set `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\Temp` (any short existing folder) and retry |
| Android build fails with `Could not close incremental caches` | Already handled: `kotlin.incremental=false` in `android/gradle.properties` (needed when the project and the Flutter package cache are on different drives) |

## Design notes

- A schedule's office cannot be changed. Cancel it and create a new one, so notifications and history stay clear. Changing the date or time always marks a schedule *Rescheduled*.
- Renaming an office does not change the name stored on its past schedules and collections.
- Push notifications use FCM registration tokens, which the Firebase Admin SDK sends to. `firebase_messaging` 17 marks this API as deprecated but still supports it.
- While the app is open, a push notification appears as an in-app banner with a **View** button. Tapping a system notification opens the related schedule or assessment and marks it read.
- Deactivating an account disables it and ends its sessions. A sign-in token issued just before can still read that office's own data for up to one hour.
