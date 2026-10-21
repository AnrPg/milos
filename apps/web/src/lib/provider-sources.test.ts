import { describe, expect, it } from "vitest";

import type { MyProviders } from "@/api/providers";
import {
  DEVICE_COLOR,
  FORMER_COLOR,
  paletteColor,
  providerColor,
  showsSource,
  sourceColor,
  sourceDirectory,
  sourceOptions,
  sourceToken,
} from "@/lib/provider-sources";

const box = {
  organization_id: "org-box",
  name: "Box Κυψέλη",
  slug: "box-kypseli",
  kind: "gym" as const,
  selected: true,
  unread_messages: 0,
  primary_color: "#d9743d",
};
const coach = { ...box, organization_id: "org-coach", name: "Νίκος Π.", slug: "nikos", kind: "coach" as const, selected: false, primary_color: null };
const providers = (list: MyProviders["providers"], former: MyProviders["former"] = []): MyProviders => ({
  selected_organization_id: list[0]?.organization_id ?? null,
  providers: list,
  former,
});

describe("provider sources (ADR-162)", () => {
  it("turns a source into the filter token", () => {
    expect(sourceToken({ kind: "organization", organization_id: "org-box" })).toBe("org-box");
    expect(sourceToken({ kind: "freeform", organization_id: null })).toBe("freeform");
    expect(sourceToken({ kind: "device", organization_id: null })).toBe("device");
  });

  it("gives each provider a stable theme series colour, never its brand colour", () => {
    expect(providerColor(box)).toBe(paletteColor(box.organization_id));
    expect(paletteColor("org-x")).toBe(paletteColor("org-x"));
    expect(paletteColor("org-x")).toMatch(/^var\(--series-\d\)$/);
  });

  it("labels providers' entries only once there are two providers to tell apart", () => {
    const single = sourceDirectory(providers([box]));
    const entry = { kind: "organization" as const, organization_id: "org-box", name: "Box Κυψέλη", former: false };
    expect(showsSource(entry, single)).toBe(false);
    expect(showsSource({ ...entry, kind: "freeform", organization_id: null }, single)).toBe(true);
    expect(showsSource({ ...entry, former: true }, single)).toBe(true);
    expect(showsSource(entry, sourceDirectory(providers([box, coach])))).toBe(true);
    expect(showsSource(entry, sourceDirectory(providers([box], [{ organization_id: "old", name: "Old", kind: "gym" }])))).toBe(true);
  });

  it("colours former providers and devices apart", () => {
    const directory = sourceDirectory(providers([box]));
    expect(sourceColor({ kind: "organization", organization_id: "org-box", name: "x", former: true }, directory)).toBe(FORMER_COLOR);
    expect(sourceColor({ kind: "device", organization_id: null, name: "Garmin", former: false }, directory)).toBe(DEVICE_COLOR);
    expect(sourceColor({ kind: "organization", organization_id: "org-box", name: "x", former: false }, directory)).toBe(providerColor(box));
  });

  it("lists sources for the filters: active, former, freeform, device", () => {
    const directory = sourceDirectory(providers([box, coach], [{ organization_id: "old", name: "Old", kind: "gym" }]));
    const labels = { freeform: "Ελεύθερη", device: "Συσκευή", former: (name: string) => `${name} (πρώην)` };
    expect(sourceOptions(directory, labels).map((option) => option.label)).toEqual([
      "Box Κυψέλη",
      "Νίκος Π.",
      "Old (πρώην)",
      "Ελεύθερη",
      "Συσκευή",
    ]);
    expect(sourceOptions(directory, labels, { device: false }).map((option) => option.value)).not.toContain("device");
  });
});
