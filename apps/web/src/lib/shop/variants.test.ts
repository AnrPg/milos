import { describe, expect, it } from "vitest";

import type { ShopOptionAxis, ShopProductSummary, ShopVariant } from "@/api/shop";

import { choose, initialSelection, isColourAxis, orderableUnits, productCard, selectedVariant, valueStates } from "./variants";

const colour: ShopOptionAxis = { name: "Χρώμα", values: ["Μαύρο", "Λευκό"] };
const size: ShopOptionAxis = { name: "Μέγεθος", values: ["XS", "S", "M", "L"] };

function variant(colourValue: string, sizeValue: string, available: number | null, extra: Partial<ShopVariant> = {}): ShopVariant {
  return {
    id: `${colourValue}-${sizeValue}`,
    title: `${colourValue} · ${sizeValue}`,
    option_values: { Χρώμα: colourValue, Μέγεθος: sizeValue },
    price_cents: 2500,
    currency: "EUR",
    stock_status: available === 0 ? "out" : "ok",
    available,
    ...extra,
  };
}

const variants = [
  variant("Μαύρο", "XS", 0),
  variant("Μαύρο", "S", 4),
  variant("Μαύρο", "M", 1),
  variant("Μαύρο", "L", 9),
  variant("Λευκό", "S", 0),
  variant("Λευκό", "M", 6),
];

describe("variant availability", () => {
  it("keeps every size and marks the sold-out, the low and the missing ones", () => {
    expect(valueStates(size, variants, { Χρώμα: "Μαύρο" })).toEqual({ XS: "sold_out", S: "low", M: "low", L: "available" });
    expect(valueStates(size, variants, { Χρώμα: "Λευκό" })).toEqual({ XS: "missing", S: "sold_out", M: "available", L: "missing" });
  });

  it("finds the chosen variant only once every axis has a value", () => {
    expect(selectedVariant([colour, size], variants, { Χρώμα: "Μαύρο" })).toBeNull();
    expect(selectedVariant([colour, size], variants, { Χρώμα: "Μαύρο", Μέγεθος: "M" })?.id).toBe("Μαύρο-M");
    expect(selectedVariant([], [variants[1]], {})?.id).toBe("Μαύρο-S");
  });

  it("opens on the first colour in stock and never guesses a size", () => {
    const allBlackOut = variants.map((item) => (item.option_values.Χρώμα === "Μαύρο" ? { ...item, available: 0, stock_status: "out" as const } : item));
    expect(initialSelection([colour, size], allBlackOut)).toEqual({ Χρώμα: "Λευκό" });
    expect(initialSelection([{ name: "Γεύση", values: ["Σοκολάτα"] }], [])).toEqual({ Γεύση: "Σοκολάτα" });
  });

  it("clears the other axes when a choice has no such combination", () => {
    expect(choose([colour, size], variants, { Χρώμα: "Μαύρο", Μέγεθος: "L" }, "Χρώμα", "Λευκό")).toEqual({ Χρώμα: "Λευκό" });
    expect(choose([colour, size], variants, { Χρώμα: "Μαύρο", Μέγεθος: "M" }, "Χρώμα", "Λευκό")).toEqual({ Χρώμα: "Λευκό", Μέγεθος: "M" });
  });

  it("caps what can be added by stock and the per-person limit", () => {
    expect(orderableUnits(variants[3], 2)).toBe(2);
    expect(orderableUnits(variants[3], null)).toBe(9);
    expect(orderableUnits(variants[0], null)).toBe(0);
    expect(orderableUnits(variant("Μαύρο", "S", null), null)).toBeNull();
  });

  it("recognises a colour axis by kind or by name", () => {
    expect(isColourAxis(colour)).toBe(true);
    expect(isColourAxis({ name: "Colour", values: [] })).toBe(true);
    expect(isColourAxis({ name: "Χρώμα", values: [], kind: "other" })).toBe(false);
  });
});

describe("grid card", () => {
  const product = (overrides: Partial<ShopProductSummary> = {}): ShopProductSummary => ({
    id: "tee",
    title: "T-shirt",
    category: "Ρούχα",
    photos: [],
    options: { axes: [colour, size] },
    variants,
    member_discount_applies: true,
    per_person_limit: null,
    is_new: true,
    published_at: null,
    ...overrides,
  });

  it("merges the colours into one card with its sizes", () => {
    expect(productCard(product())).toMatchObject({ colours: ["Μαύρο", "Λευκό"], sizeCount: 4, fromPriceCents: 2500, hasPriceRange: false, flag: { kind: "new" } });
  });

  it("says «Τελευταία n» when few units are left, and sold out when none", () => {
    expect(productCard(product({ variants: [variant("Μαύρο", "S", 2), variant("Μαύρο", "M", 1)] })).flag).toEqual({ kind: "last", units: 3 });
    expect(productCard(product({ variants: [variant("Μαύρο", "S", 0)] })).flag).toEqual({ kind: "sold_out" });
    expect(productCard(product({ is_new: false, variants: [variant("Μαύρο", "S", null)] })).flag).toBeNull();
  });

  it("shows a price range from the cheapest variant", () => {
    const card = productCard(product({ variants: [variant("Μαύρο", "S", 9), variant("Μαύρο", "L", 9, { price_cents: 2800, id: "x" })] }));
    expect(card).toMatchObject({ fromPriceCents: 2500, hasPriceRange: true });
  });
});
