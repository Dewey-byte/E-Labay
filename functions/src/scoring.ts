/**
 * Pure scoring and validation logic (no Firebase imports) so it can be unit
 * tested. The Flutter app mirrors this in `lib/core/utils/scoring.dart` for
 * the preview only; this implementation is authoritative.
 */

export const CATEGORIES = ["biodegradable", "non_biodegradable", "recyclable", "residual"] as const;
export type Category = (typeof CATEGORIES)[number];

export const RESULTS = ["proper", "improper", "not_applicable"] as const;
export type SegregationResult = (typeof RESULTS)[number];

export type SegregationResults = Record<Category, SegregationResult>;

export interface ScoringConfig {
  properPoints: number;
  improperPoints: number;
}

export const DEFAULT_SCORING: ScoringConfig = { properPoints: 10, improperPoints: 0 };
export const MAX_POINTS_PER_CATEGORY = 100;

export interface ScoreBreakdown {
  points: number;
  maxPoints: number;
  properCount: number;
  improperCount: number;
  applicableCount: number;
}

export class ValidationError extends Error {}

function clampPoints(value: unknown, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.min(MAX_POINTS_PER_CATEGORY, Math.max(0, Math.trunc(value)));
}

/** Reads `config/scoring`, falling back to the defaults for missing values. */
export function parseScoringConfig(data: unknown): ScoringConfig {
  const raw = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
  const properPoints = clampPoints(raw.properPoints, DEFAULT_SCORING.properPoints);
  const improperPoints = Math.min(
    properPoints,
    clampPoints(raw.improperPoints, DEFAULT_SCORING.improperPoints),
  );
  return { properPoints, improperPoints };
}

/**
 * Validates the client payload: every category must be present exactly once
 * with a known result, and no unknown keys are allowed.
 */
export function validateSegregationResults(input: unknown): SegregationResults {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ValidationError("segregationResults must be an object.");
  }
  const raw = input as Record<string, unknown>;
  for (const key of Object.keys(raw)) {
    if (!(CATEGORIES as readonly string[]).includes(key)) {
      throw new ValidationError(`Unknown waste category "${key}".`);
    }
  }
  const results = {} as SegregationResults;
  for (const category of CATEGORIES) {
    const value = raw[category];
    if (typeof value !== "string" || !(RESULTS as readonly string[]).includes(value)) {
      throw new ValidationError(`Missing or invalid assessment for "${category}".`);
    }
    results[category] = value as SegregationResult;
  }
  return results;
}

/**
 * Proper category -> properPoints, improper -> improperPoints, not applicable
 * -> excluded from both the score and the maximum.
 */
export function scoreAssessment(results: SegregationResults, config: ScoringConfig): ScoreBreakdown {
  let properCount = 0;
  let improperCount = 0;
  for (const category of CATEGORIES) {
    if (results[category] === "proper") properCount++;
    else if (results[category] === "improper") improperCount++;
  }
  const applicableCount = properCount + improperCount;
  return {
    points: properCount * config.properPoints + improperCount * config.improperPoints,
    maxPoints: applicableCount * config.properPoints,
    properCount,
    improperCount,
    applicableCount,
  };
}

/**
 * Evidence photos must be Firebase Storage download URLs under
 * `collections/{officeId}/{scheduleId}/`. Local emulator URLs are accepted
 * only when [allowLocal] is set (i.e. while running in the emulator).
 */
export function validateEvidenceUrls(
  input: unknown,
  officeId: string,
  scheduleId: string,
  maxCount: number,
  allowLocal = false,
): string[] {
  if (input === undefined || input === null) return [];
  if (!Array.isArray(input)) throw new ValidationError("evidenceImageUrls must be a list.");
  if (input.length > maxCount) {
    throw new ValidationError(`At most ${maxCount} evidence photos are allowed.`);
  }
  const expectedPath = encodeURIComponent(`collections/${officeId}/${scheduleId}/`);
  return input.map((value) => {
    if (typeof value !== "string" || value.length > 2048) {
      throw new ValidationError("Invalid evidence photo URL.");
    }
    let url: URL;
    try {
      url = new URL(value);
    } catch {
      throw new ValidationError("Invalid evidence photo URL.");
    }
    const isStorageHost =
      url.protocol === "https:" &&
      (url.hostname === "firebasestorage.googleapis.com" || url.hostname.endsWith(".firebasestorage.app"));
    const isEmulator =
      allowLocal && url.protocol === "http:" && (url.hostname === "127.0.0.1" || url.hostname === "localhost");
    if (!(isStorageHost || isEmulator) || !url.pathname.includes(`/o/${expectedPath}`)) {
      throw new ValidationError("Evidence photos must be uploaded for this collection.");
    }
    return value;
  });
}

/** Trimmed string with a maximum length; empty strings allowed when optional. */
export function cleanString(
  value: unknown,
  field: string,
  { max, required }: { max: number; required: boolean },
): string {
  if (value === undefined || value === null) {
    if (required) throw new ValidationError(`${field} is required.`);
    return "";
  }
  if (typeof value !== "string") throw new ValidationError(`${field} must be text.`);
  const trimmed = value.trim();
  if (required && trimmed.length === 0) throw new ValidationError(`${field} is required.`);
  if (trimmed.length > max) throw new ValidationError(`${field} must be at most ${max} characters.`);
  return trimmed;
}
