import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import { documentsRequired, type DocumentItem, type DocumentTemplate, type HealthRow } from "@/api/documents";

import {
  blocksBookingOnPublish,
  gateReady,
  gateSteps,
  healthContentType,
  healthSummary,
  lastValidDay,
  myMissingCount,
  normalizeStrokes,
  requestedAtByUser,
  sortMyDocuments,
  staffRows,
  stepKey,
  typedNameValid,
} from "./documents-model";

const template = (id: string, extra: Partial<DocumentTemplate> = {}): DocumentTemplate => ({
  id,
  kind: "terms",
  title: id,
  requirement: "mandatory",
  status: "active",
  current_version_id: `${id}-v1`,
  current_version_number: 1,
  required_version_number: 1,
  archived_at: null,
  inserted_at: "2026-10-01T00:00:00Z",
  updated_at: "2026-10-01T00:00:00Z",
  ...extra,
});

const health = (status: HealthRow["status"]): HealthRow => ({ user_id: status, display_name: status, handle: null, status, certificate: null });

const item = (id: string, extra: Partial<DocumentItem> = {}): DocumentItem => ({
  template_id: id,
  kind: "terms",
  title: id,
  requirement: "mandatory",
  current_version_id: `${id}-v1`,
  current_version_number: 1,
  status: "signed",
  outstanding: false,
  requested: false,
  signature: null,
  ...extra,
});

describe("staff rows", () => {
  it("counts who is missing per document and adds the health certificate last", () => {
    const rows = staffRows(
      [template("terms"), template("old", { status: "archived" })],
      [{ template_id: "terms", signed: 5, outstanding: 2, clients: [] }],
      { required: true, rows: [health("missing"), health("expired"), health("expiring"), health("valid")] },
    );
    expect(rows).toEqual([
      expect.objectContaining({ kind: "document", missing: 2, signed: 5 }),
      { kind: "health", required: true, missing: 2, expiring: 1 },
    ]);
  });

  it("leaves the health row out for staff who cannot see certificates", () => {
    expect(staffRows([template("terms")], undefined, null)).toEqual([expect.objectContaining({ kind: "document", missing: 0 })]);
  });

  it("summarises certificates", () => {
    expect(healthSummary([health("valid")])).toEqual({ missing: 0, expiring: 0 });
  });
});

describe("publish warning", () => {
  it("warns only for a mandatory, major publish while the booking gate is on", () => {
    expect(blocksBookingOnPublish("mandatory", { block_booking_on_unsigned: true })).toBe(true);
    expect(blocksBookingOnPublish("mandatory", null)).toBe(true);
    expect(blocksBookingOnPublish("optional", { block_booking_on_unsigned: true })).toBe(false);
    expect(blocksBookingOnPublish("mandatory", { block_booking_on_unsigned: false })).toBe(false);
    expect(blocksBookingOnPublish("mandatory", { block_booking_on_unsigned: true }, "minor")).toBe(false);
  });
});

describe("requests", () => {
  it("keeps the latest pending request per client", () => {
    const base = { template_id: "t", batch_id: null, audience: "person" as const, requested_by_id: null, signature_id: null, closed_at: null };
    const map = requestedAtByUser([
      { ...base, id: "1", user_id: "u", status: "pending", requested_at: "2026-10-20T10:00:00Z" },
      { ...base, id: "2", user_id: "u", status: "pending", requested_at: "2026-10-25T10:00:00Z" },
      { ...base, id: "3", user_id: "v", status: "cancelled", requested_at: "2026-10-25T10:00:00Z" },
    ]);
    expect(map.get("u")).toBe("2026-10-25T10:00:00Z");
    expect(map.has("v")).toBe(false);
  });
});

describe("client documents", () => {
  it("counts mandatory documents and a missing certificate the box asks for", () => {
    const overview = { documents: [], outstanding: 1, health_certificate: { required: true, status: "expired" as const, certificate: null } };
    expect(myMissingCount(overview)).toBe(2);
    expect(myMissingCount({ ...overview, health_certificate: { required: false, status: "missing", certificate: null } })).toBe(1);
    expect(myMissingCount(null)).toBe(0);
  });

  it("puts outstanding documents first and hides unpublished ones", () => {
    const sorted = sortMyDocuments([
      item("signed"),
      item("draft", { current_version_id: null }),
      item("asked", { status: "unsigned", requested: true, requirement: "optional" }),
      item("must", { status: "resign_required", outstanding: true }),
    ]);
    expect(sorted.map((entry) => entry.template_id)).toEqual(["must", "asked", "signed"]);
  });
});

describe("booking gate", () => {
  it("reads the 409 and lists documents then the certificate", () => {
    const error = new ApiError(409, "x", {
      code: "documents_required",
      params: { documents: [{ template_id: "t", title: "Όροι", kind: "terms", reason: "unsigned" }], health_certificate: "expired" },
    });
    const required = documentsRequired(error);
    expect(required).not.toBeNull();
    const steps = gateSteps(required!);
    expect(steps.map(stepKey)).toEqual(["t", "health"]);
    expect(gateReady(steps, new Set(["t"]))).toBe(false);
    expect(gateReady(steps, new Set(["t", "health"]))).toBe(true);
    expect(documentsRequired(new ApiError(409, "x", { code: "slot_full" }))).toBeNull();
  });
});

describe("signature input", () => {
  it("rounds, clamps and drops repeated points", () => {
    expect(normalizeStrokes([[[1.4, 2.6], [1.2, 3.1], [700, -5]]], 600, 200)).toEqual([[[1, 3], [600, 0]]]);
  });

  it("keeps at most 100 strokes and 5,000 points", () => {
    const many = Array.from({ length: 150 }, (_, index) => [[index, 1]]);
    expect(normalizeStrokes(many)).toHaveLength(100);
    const long = [Array.from({ length: 6000 }, (_, index) => [index % 600, Math.floor(index / 600)])];
    expect(normalizeStrokes(long)[0]).toHaveLength(5000);
  });

  it("accepts a typed name of 2 to 120 characters", () => {
    expect(typedNameValid(" Μ ")).toBe(false);
    expect(typedNameValid("Μαρία Κ.")).toBe(true);
    expect(typedNameValid("x".repeat(121))).toBe(false);
  });
});

describe("health upload", () => {
  it("accepts PDF and images, by type or extension", () => {
    expect(healthContentType({ type: "image/jpeg", name: "a" })).toBe("image/jpeg");
    expect(healthContentType({ type: "", name: "scan.PDF" })).toBe("application/pdf");
    expect(healthContentType({ type: "image/heic", name: "a.heic" })).toBeNull();
  });

  it("shows the last valid day", () => {
    expect(lastValidDay("2027-10-27")).toBe("2027-10-26");
  });
});
