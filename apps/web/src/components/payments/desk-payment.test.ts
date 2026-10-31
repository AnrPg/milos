import { describe, expect, it } from "vitest";

import type { PublicPackage } from "@/api/my-payments";

import { deskMode, deskPackages, holdDateLabel, localDate } from "./desk-payment";

const pkg = (id: string, cents: number) => ({ id, name: id, base_price_cents: cents }) as unknown as PublicPackage;

describe("desk payment (ADR-291)", () => {
  it("reads the box's date as a local date", () => {
    const date = localDate("2026-11-14");
    expect(date?.getFullYear()).toBe(2026);
    expect(date?.getMonth()).toBe(10);
    expect(date?.getDate()).toBe(14);
    expect(localDate("14/11/2026")).toBeNull();
  });

  it("names the last day held in the person's language", () => {
    expect(holdDateLabel("el", "2026-11-14")).toBe("14 Νοεμβρίου");
    expect(holdDateLabel("en", "2026-11-14")).toBe("November 14");
  });

  it("asks at the desk only when the box takes no online payments", () => {
    expect(deskMode({ online_payments: false })).toBe(true);
    expect(deskMode({ online_payments: true })).toBe(false);
    expect(deskMode(null)).toBe(false);
  });

  it("lists the paid packages for the desk, none when paying online", () => {
    const packages = [pkg("monthly", 7000), pkg("free", 0)];
    expect(deskPackages({ online_payments: false, packages }).map((p) => p.id)).toEqual(["monthly"]);
    expect(deskPackages({ online_payments: true, packages })).toEqual([]);
  });
});
