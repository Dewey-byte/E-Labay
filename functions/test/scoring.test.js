// Unit tests for the authoritative scoring/validation logic.
// Run with `npm test` (builds TypeScript first).
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_SCORING,
  ValidationError,
  cleanString,
  parseScoringConfig,
  scoreAssessment,
  validateEvidenceUrls,
  validateSegregationResults,
} = require("../lib/scoring");

const all = (result) => ({
  biodegradable: result,
  non_biodegradable: result,
  recyclable: result,
  residual: result,
});

test("all categories properly segregated earns the 40-point maximum", () => {
  const score = scoreAssessment(all("proper"), DEFAULT_SCORING);
  assert.deepEqual(score, { points: 40, maxPoints: 40, properCount: 4, improperCount: 0, applicableCount: 4 });
});

test("improper categories earn 0 and N/A categories are excluded", () => {
  const score = scoreAssessment(
    { biodegradable: "proper", non_biodegradable: "improper", recyclable: "not_applicable", residual: "proper" },
    DEFAULT_SCORING,
  );
  assert.equal(score.points, 20);
  assert.equal(score.maxPoints, 30);
  assert.equal(score.applicableCount, 3);
  assert.equal(score.improperCount, 1);
});

test("all not applicable scores zero out of zero", () => {
  const score = scoreAssessment(all("not_applicable"), DEFAULT_SCORING);
  assert.equal(score.points, 0);
  assert.equal(score.maxPoints, 0);
  assert.equal(score.applicableCount, 0);
});

test("scoring uses configured point values", () => {
  const score = scoreAssessment(
    { biodegradable: "proper", non_biodegradable: "improper", recyclable: "proper", residual: "improper" },
    { properPoints: 15, improperPoints: 5 },
  );
  assert.equal(score.points, 40);
  assert.equal(score.maxPoints, 60);
});

test("parseScoringConfig falls back to defaults and clamps values", () => {
  assert.deepEqual(parseScoringConfig(undefined), DEFAULT_SCORING);
  assert.deepEqual(parseScoringConfig({ properPoints: 500, improperPoints: -3 }), { properPoints: 100, improperPoints: 0 });
  assert.deepEqual(parseScoringConfig({ properPoints: 8, improperPoints: 20 }), { properPoints: 8, improperPoints: 8 });
  assert.deepEqual(parseScoringConfig({ properPoints: "10" }), DEFAULT_SCORING);
});

test("validateSegregationResults requires every category with a known result", () => {
  assert.deepEqual(validateSegregationResults(all("proper")), all("proper"));
  assert.throws(() => validateSegregationResults({ biodegradable: "proper" }), ValidationError);
  assert.throws(() => validateSegregationResults({ ...all("proper"), recyclable: "great" }), ValidationError);
  assert.throws(() => validateSegregationResults({ ...all("proper"), hazardous: "proper" }), ValidationError);
  assert.throws(() => validateSegregationResults(null), ValidationError);
  assert.throws(() => validateSegregationResults(["proper"]), ValidationError);
});

test("validateEvidenceUrls only accepts storage URLs for this collection", () => {
  const good =
    "https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/collections%2Foffice1%2Fsched1%2F1.jpg?alt=media&token=abc";
  assert.deepEqual(validateEvidenceUrls([good], "office1", "sched1", 3), [good]);
  assert.deepEqual(validateEvidenceUrls(undefined, "office1", "sched1", 3), []);

  const otherSchedule = good.replace("sched1", "sched2");
  assert.throws(() => validateEvidenceUrls([otherSchedule], "office1", "sched1", 3), ValidationError);
  assert.throws(() => validateEvidenceUrls(["https://evil.example.com/o/collections%2Foffice1%2Fsched1%2Fx"], "office1", "sched1", 3), ValidationError);
  assert.throws(() => validateEvidenceUrls([good, good, good, good], "office1", "sched1", 3), ValidationError);
  assert.throws(() => validateEvidenceUrls("not-a-list", "office1", "sched1", 3), ValidationError);

  const local = "http://127.0.0.1:9199/v0/b/demo/o/collections%2Foffice1%2Fsched1%2F1.jpg?alt=media";
  assert.throws(() => validateEvidenceUrls([local], "office1", "sched1", 3), ValidationError);
  assert.deepEqual(validateEvidenceUrls([local], "office1", "sched1", 3, true), [local]);
});

test("cleanString trims, enforces length and requiredness", () => {
  assert.equal(cleanString("  hi  ", "Name", { max: 5, required: true }), "hi");
  assert.equal(cleanString(undefined, "Remarks", { max: 5, required: false }), "");
  assert.throws(() => cleanString("   ", "Name", { max: 5, required: true }), ValidationError);
  assert.throws(() => cleanString("toolong", "Name", { max: 5, required: true }), ValidationError);
  assert.throws(() => cleanString(42, "Name", { max: 5, required: true }), ValidationError);
});
