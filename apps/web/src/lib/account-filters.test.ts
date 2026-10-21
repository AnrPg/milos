import { describe, expect, it } from "vitest";

import {
  DEFAULT_PROGRESS_FILTER,
  DEFAULT_VAULT_FILTER,
  parseProgressFilter,
  parseVaultFilter,
  vaultFilterCount,
} from "@/lib/account-filters";

describe("Vault and Πρόοδος filters across providers", () => {
  it("defaults to every provider", () => {
    expect(parseVaultFilter(null)).toEqual(DEFAULT_VAULT_FILTER);
    expect(parseProgressFilter(null)).toEqual(DEFAULT_PROGRESS_FILTER);
    expect(DEFAULT_PROGRESS_FILTER.sources).toEqual([]);
  });

  it("keeps known disciplines and a valid range only", () => {
    expect(parseVaultFilter({ disciplines: ["crossfit", "chess"], benchmark: "fran", date_from: "nope" })).toMatchObject({
      disciplines: ["crossfit"],
      benchmark: "fran",
      date_from: null,
    });
    expect(parseProgressFilter({ range: "10y", sources: "org-1,device" })).toEqual({
      range: DEFAULT_PROGRESS_FILTER.range,
      sources: ["org-1", "device"],
      exercise: null,
    });
  });

  it("counts Vault facets with dates once", () => {
    expect(vaultFilterCount({ ...DEFAULT_VAULT_FILTER, date_from: "2026-01-01", date_to: "2026-02-01", sources: ["freeform"] })).toBe(2);
  });
});
