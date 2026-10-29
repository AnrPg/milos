import type {
  DocumentItem,
  DocumentKind,
  DocumentRequirement,
  DocumentSettings,
  DocumentsRequired,
  DocumentTemplate,
  HealthContentType,
  HealthRow,
  HealthStatus,
  MyDocumentsOverview,
  OutstandingRow,
  SignatureRequest,
} from "@/api/documents";
import { HEALTH_CONTENT_TYPES } from "@/api/documents";

// Pure rules of the documents screens (mockup s7, option B, with the product
// owner's change: each document is «Υποχρεωτικό» or «Προαιρετικό», and only
// mandatory ones block booking).

/** Staff list rows: documents in the API's order (active first), then the health certificate. */
export type StaffRow =
  | { kind: "document"; template: DocumentTemplate; missing: number; signed: number }
  | { kind: "health"; required: boolean; missing: number; expiring: number };

export function staffRows(
  templates: DocumentTemplate[],
  outstanding: OutstandingRow[] | undefined,
  health: { required: boolean; rows: HealthRow[] } | null,
): StaffRow[] {
  const byTemplate = new Map((outstanding ?? []).map((row) => [row.template_id, row]));
  const rows: StaffRow[] = templates
    .filter((template) => template.status === "active")
    .map((template) => {
      const row = byTemplate.get(template.id);
      return { kind: "document", template, missing: row?.outstanding ?? 0, signed: row?.signed ?? 0 };
    });
  if (health) {
    const summary = healthSummary(health.rows);
    rows.push({ kind: "health", required: health.required, missing: summary.missing, expiring: summary.expiring });
  }
  return rows;
}

/** Missing = no certificate or an expired one; expiring = inside the reminder window. */
export function healthSummary(rows: HealthRow[]) {
  let missing = 0;
  let expiring = 0;
  for (const row of rows) {
    if (row.status === "missing" || row.status === "expired") missing += 1;
    else if (row.status === "expiring") expiring += 1;
  }
  return { missing, expiring };
}

export function healthOutstanding(rows: HealthRow[]) {
  return rows.filter((row) => row.status === "missing" || row.status === "expired");
}

/**
 * The proposed default while the product owner decides (ADR-252
 * consequences): publishing a mandatory document while the booking gate is on
 * blocks unsigned clients from booking until they sign, so staff are told.
 */
export function blocksBookingOnPublish(
  requirement: DocumentRequirement,
  settings: Pick<DocumentSettings, "block_booking_on_unsigned"> | null | undefined,
  changeKind: "major" | "minor" = "major",
) {
  return requirement === "mandatory" && changeKind === "major" && settings?.block_booking_on_unsigned !== false;
}

/** When each pending request was sent, by client. */
export function requestedAtByUser(requests: SignatureRequest[]) {
  const map = new Map<string, string>();
  for (const request of requests) {
    if (request.status !== "pending") continue;
    const known = map.get(request.user_id);
    if (!known || known < request.requested_at) map.set(request.user_id, request.requested_at);
  }
  return map;
}

// ── Client ────────────────────────────────────────────────────────────────

/** The health certificate counts as missing for booking only when the box asks for it. */
export function myHealthOutstanding(overview: MyDocumentsOverview | null | undefined) {
  const health = overview?.health_certificate;
  return Boolean(health?.required && (health.status === "missing" || health.status === "expired"));
}

/** What the Box card «Λείπουν N έγγραφα» counts: mandatory documents not signed, plus the certificate. */
export function myMissingCount(overview: MyDocumentsOverview | null | undefined) {
  if (!overview) return 0;
  return overview.outstanding + (myHealthOutstanding(overview) ? 1 : 0);
}

/** Outstanding first, then what staff asked for, then the rest; the API order otherwise. */
export function sortMyDocuments(documents: DocumentItem[]) {
  const rank = (item: DocumentItem) => (item.outstanding ? 0 : item.status !== "signed" && item.requested ? 1 : 2);
  return documents
    .filter((item) => item.current_version_id)
    .map((item, index) => ({ item, index }))
    .sort((a, b) => rank(a.item) - rank(b.item) || a.index - b.index)
    .map(({ item }) => item);
}

/** One step of the booking sheet when the booking answered `documents_required`. */
export type GateStep = { kind: "document"; templateId: string; title: string; reason: string } | { kind: "health"; status: HealthStatus };

export function gateSteps(required: DocumentsRequired): GateStep[] {
  const steps: GateStep[] = required.documents.map((document) => ({
    kind: "document",
    templateId: document.template_id,
    title: document.title,
    reason: document.reason,
  }));
  if (required.health_certificate) steps.push({ kind: "health", status: required.health_certificate });
  return steps;
}

export function stepKey(step: GateStep) {
  return step.kind === "health" ? "health" : step.templateId;
}

export function gateReady(steps: GateStep[], done: ReadonlySet<string>) {
  return steps.every((step) => done.has(stepKey(step)));
}

// ── Signature pad ─────────────────────────────────────────────────────────

export const PAD_WIDTH = 600;
export const PAD_HEIGHT = 200;
const MAX_STROKES = 100;
const MAX_POINTS = 5000;

/**
 * The drawn signature as the API accepts it (ADR-252 §3): integer points
 * inside the box, at most 100 strokes and 5,000 points in all. Points are
 * clamped and rounded; consecutive duplicates are dropped; extra strokes or
 * points past the limits are left out.
 */
export function normalizeStrokes(strokes: number[][][], width = PAD_WIDTH, height = PAD_HEIGHT): number[][][] {
  const out: number[][][] = [];
  let total = 0;
  for (const stroke of strokes) {
    if (out.length >= MAX_STROKES || total >= MAX_POINTS) break;
    const points: number[][] = [];
    for (const [x, y] of stroke) {
      if (total + points.length >= MAX_POINTS) break;
      const point = [clamp(Math.round(x), 0, width), clamp(Math.round(y), 0, height)];
      const last = points[points.length - 1];
      if (last && last[0] === point[0] && last[1] === point[1]) continue;
      points.push(point);
    }
    if (points.length > 0) {
      out.push(points);
      total += points.length;
    }
  }
  return out;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

/** A typed name the API accepts: 2–120 characters once trimmed. */
export function typedNameValid(name: string) {
  const trimmed = name.trim().replace(/\s+/g, " ");
  return trimmed.length >= 2 && trimmed.length <= 120;
}

// ── Health certificate upload ─────────────────────────────────────────────

export const HEALTH_MAX_BYTES = 10 * 1024 * 1024;

export function healthContentType(file: Pick<File, "type" | "name">): HealthContentType | null {
  const type = file.type.toLowerCase();
  if ((HEALTH_CONTENT_TYPES as string[]).includes(type)) return type as HealthContentType;
  const extension = file.name.toLowerCase().split(".").pop();
  if (extension === "pdf") return "application/pdf";
  if (extension === "jpg" || extension === "jpeg") return "image/jpeg";
  if (extension === "png") return "image/png";
  if (extension === "webp") return "image/webp";
  return null;
}

/** «today» as the box's calendar day (YYYY-MM-DD) in the device's zone. */
export function isoToday(now = new Date()) {
  const offset = now.getTimezoneOffset() * 60_000;
  return new Date(now.getTime() - offset).toISOString().slice(0, 10);
}

/** The last day a certificate is valid: the day before `expires_on`. */
export function lastValidDay(expiresOn: string) {
  const date = new Date(`${expiresOn}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}

/** A day (YYYY-MM-DD) or instant shown as a short local date. */
export function shortDate(value: string, locale: string) {
  const day = /^\d{4}-\d{2}-\d{2}$/.test(value);
  const date = day ? new Date(`${value}T00:00:00Z`) : new Date(value);
  return new Intl.DateTimeFormat(locale, { day: "numeric", month: "numeric", year: "numeric", ...(day ? { timeZone: "UTC" } : {}) }).format(date);
}

export const DOCUMENT_KINDS: DocumentKind[] = ["terms", "waiver", "privacy", "health_certificate", "other"];
