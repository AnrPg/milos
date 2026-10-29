import { describe, expect, it } from "vitest";

import {
  changesFor,
  doneGroups,
  fromRegistry,
  groupFields,
  isValidAfm,
  groupOfMissing,
  localTerm,
  nextStep,
  progress,
  summaryValues,
} from "./identity-model";

const GR = { country: "GR", required_fields: ["legal_name", "street", "postal_code", "city", "tax_id", "tax_office"], tax_office: true, tax_system: "vat" as const };
const DE = { country: "DE", required_fields: ["legal_name", "street", "postal_code", "city", "tax_id_or_vat_number"], tax_office: false, tax_system: "vat" as const };
const US = { country: "US", required_fields: ["legal_name", "street", "postal_code", "city", "region"], tax_office: false, tax_system: "sales_tax" as const };
const CH = { country: "CH", required_fields: ["legal_name", "street", "postal_code", "city"], tax_office: false, tax_system: "vat" as const };

const keys = (fields: { key: string }[]) => fields.map((field) => field.key);

describe("groupFields", () => {
  it("asks Greece for ΑΦΜ and ΔΟΥ, the branch code, and no separate VAT number", () => {
    const groups = groupFields(GR, "standard");
    expect(keys(groups.business)).toEqual(["legal_name", "trade_name", "tax_id", "tax_office"]);
    expect(groups.business.find((field) => field.key === "tax_office")?.required).toBe(true);
    expect(keys(groups.tax)).toContain("branch_code");
    expect(keys(groups.tax)).not.toContain("vat_number");
  });

  it("asks a VAT-registered German business for its VAT number, a small business not", () => {
    expect(keys(groupFields(DE, "standard").tax)).toContain("vat_number");
    expect(keys(groupFields(DE, "small_business").tax)).not.toContain("vat_number");
    expect(groupFields(DE, "standard").business.find((field) => field.key === "tax_id")?.required).toBe(true);
  });

  it("asks the US for a state and Switzerland for a QR-IBAN", () => {
    expect(keys(groupFields(US, "standard").address)).toContain("region");
    expect(keys(groupFields(US, "standard").tax)).not.toContain("vat_number");
    expect(keys(groupFields(CH, "standard").tax)).toContain("qr_iban");
    expect(keys(groupFields(GR, "standard").tax)).not.toContain("qr_iban");
  });
});

describe("rows", () => {
  it("maps missing fields to their row", () => {
    expect(groupOfMissing("tax_id_or_vat_number")).toBe("business");
    expect(groupOfMissing("region")).toBe("address");
    expect(groupOfMissing("registration_number")).toBe("tax");
    expect(groupOfMissing("country_code")).toBeNull();
  });

  it("counts the country and every row with nothing missing", () => {
    expect(progress({ identity: null, missing: ["country_code"] })).toBe(0);
    const status = { identity: { id: "x" } as never, missing: ["tax_id", "street"] };
    expect([...doneGroups(status)]).toEqual(["tax"]);
    expect(progress(status)).toBe(50);
    expect(progress({ identity: { id: "x" } as never, missing: [] })).toBe(100);
  });
});

describe("changesFor", () => {
  it("clears empty text and fills the Greek VAT number from the ΑΦΜ", () => {
    const tax = groupFields(GR, "standard").tax;
    const changes = changesFor(tax, { vat_scheme: "standard", tax_id: "801234567", activity_code: " ", branch_code: "" }, "GR");
    expect(changes).toMatchObject({ vat_scheme: "standard", vat_number: "EL801234567", activity_code: null, branch_code: 0 });
    expect(changesFor(tax, { vat_scheme: "exempt", tax_id: "801234567" }, "GR").vat_number).toBeNull();
  });

  it("sends only the row's fields elsewhere", () => {
    const changes = changesFor(groupFields(DE, "standard").address, { street: "Torstraße 101", city: "Berlin", legal_name: "X" }, "DE");
    expect(changes).toEqual({ street: "Torstraße 101", postal_code: null, city: "Berlin" });
  });
});

describe("summary and next step", () => {
  it("shows the first required values", () => {
    expect(summaryValues(groupFields(GR, "standard").business, { legal_name: "ΚΥΨΕΛΗ", trade_name: "Box", tax_id: "801234567", tax_office: "Ζ΄ Αθηνών" })).toEqual([
      "ΚΥΨΕΛΗ",
      "801234567",
      "Ζ΄ Αθηνών",
    ]);
  });

  it("names the step the country's law asks for next", () => {
    expect(nextStep({ authority: "mydata", till_device: "none", register: "standard" })).toBe("mydata");
    expect(nextStep({ authority: "none", till_device: "tse", register: "standard" })).toBe("tse");
    expect(nextStep({ authority: "none", till_device: "none", register: "nf525" })).toBe("nf525");
    expect(nextStep({ authority: "none", till_device: "sign_fr", register: "nf525" })).toBe("signFr");
    expect(nextStep({ authority: "none", till_device: "none", register: "standard" })).toBe("none");
  });

  it("knows the local names of the fields", () => {
    expect(localTerm("GR", "tax_id")).toBe("ΑΦΜ");
    expect(localTerm("DE", "vat_number")).toBe("USt-IdNr.");
    expect(localTerm("GB", "tax_office")).toBeNull();
  });
});

describe("isValidAfm (ADR-265)", () => {
  it("checks the ninth digit against the weighted sum of the first eight", () => {
    expect(isValidAfm("090000045")).toBe(true);
    expect(isValidAfm(" 094014201 ")).toBe(true);
    expect(isValidAfm("090000046")).toBe(false);
    expect(isValidAfm("000000000")).toBe(false);
    expect(isValidAfm("09000004")).toBe(false);
    expect(isValidAfm("EL090000045")).toBe(false);
  });
});

describe("fromRegistry (ADR-265)", () => {
  const business = {
    legal_name: " ΚΥΨΕΛΗ Ι.Κ.Ε. ",
    trade_name: null,
    tax_office: "Ζ' ΑΘΗΝΩΝ",
    street: "ΦΩΚΙΩΝΟΣ ΝΕΓΡΗ",
    building_number: "12",
    postal_code: "11361",
    city: "ΑΘΗΝΑ",
    activity_code: "93130000",
  };

  it("fills the row's fields and keeps address and ΚΑΔ for later rows", () => {
    expect(fromRegistry(business, {})).toEqual({
      shown: { legal_name: "ΚΥΨΕΛΗ Ι.Κ.Ε.", tax_office: "Ζ' ΑΘΗΝΩΝ" },
      later: { street: "ΦΩΚΙΩΝΟΣ ΝΕΓΡΗ 12", postal_code: "11361", city: "ΑΘΗΝΑ", activity_code: "93130000" },
    });
  });

  it("never overwrites what the later rows already have", () => {
    expect(fromRegistry(business, { city: "Πειραιάς", activity_code: "93110000" }).later).toEqual({
      street: "ΦΩΚΙΩΝΟΣ ΝΕΓΡΗ 12",
      postal_code: "11361",
    });
  });
});
