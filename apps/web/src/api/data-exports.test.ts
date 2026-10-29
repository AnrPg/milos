import { beforeEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();

vi.mock("@/api/client", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/client")>();
  return { ...actual, apiRequest: (...args: unknown[]) => apiRequest(...args) };
});

import { ApiError } from "@/api/client";
import {
  dataExportRefusal,
  fetchDataExports,
  latestDataExport,
  requestDataExport,
  type DataExport,
} from "@/api/data-exports";

const item = (id: string, requested_at: string, status: DataExport["status"] = "ready"): DataExport => ({
  id,
  status,
  requested_at,
  completed_at: null,
  expires_at: null,
  record_count: null,
  file: null,
});

describe("data export requests (ADR-267)", () => {
  beforeEach(() => apiRequest.mockReset());

  it("lists and asks for exports on the account, never a box", async () => {
    apiRequest.mockResolvedValueOnce({ exports: [item("e-1", "2026-10-29T10:00:00Z")] });
    expect(await fetchDataExports("t")).toEqual([item("e-1", "2026-10-29T10:00:00Z")]);
    expect(apiRequest).toHaveBeenLastCalledWith("/me/data-exports", { token: "t", scope: "account" });

    apiRequest.mockResolvedValueOnce({ export: item("e-2", "2026-10-29T11:00:00Z", "pending") });
    expect((await requestDataExport("t")).id).toBe("e-2");
    expect(apiRequest).toHaveBeenLastCalledWith("/me/data-exports", { method: "POST", token: "t", scope: "account" });
  });

  it("tells a request in progress from the daily limit", () => {
    expect(dataExportRefusal(new ApiError(409, "", { code: "export_in_progress" }))).toEqual({ kind: "in_progress" });
    expect(
      dataExportRefusal(
        new ApiError(429, "", { code: "export_rate_limited", retry_at: "2026-10-30T10:00:00Z" } as never),
      ),
    ).toEqual({ kind: "rate_limited", retryAt: "2026-10-30T10:00:00Z" });
    // The router's own limit answers 429 without a time.
    expect(dataExportRefusal(new ApiError(429, "", { code: "rate_limited" }))).toEqual({
      kind: "rate_limited",
      retryAt: null,
    });
    expect(dataExportRefusal(new ApiError(500, "", {}))).toBeNull();
    expect(dataExportRefusal(new Error("offline"))).toBeNull();
  });

  it("shows the newest request", () => {
    expect(latestDataExport(undefined)).toBeNull();
    expect(latestDataExport([])).toBeNull();
    const newest = item("new", "2026-10-29T12:00:00Z");
    expect(latestDataExport([item("old", "2026-10-20T12:00:00Z"), newest])).toEqual(newest);
  });
});
