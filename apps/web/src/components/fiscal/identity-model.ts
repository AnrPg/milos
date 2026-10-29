import type { BusinessIdentity, CountryProfile, IdentityChanges, IdentityStatus } from "@/api/fiscal";

/**
 * Mockup s1, option C (ADR-240): the billing details as a checklist of four
 * rows (country, business, address, tax). The country comes first and
 * decides which fields the other three ask for; each row opens only its own
 * fields.
 */

export type GroupKey = "business" | "address" | "tax";
export const GROUPS: readonly GroupKey[] = ["business", "address", "tax"];

export type FieldKey =
  | "legal_name"
  | "trade_name"
  | "tax_id"
  | "tax_office"
  | "street"
  | "postal_code"
  | "city"
  | "region"
  | "vat_scheme"
  | "vat_number"
  | "registration_number"
  | "activity_code"
  | "branch_code"
  | "iban"
  | "qr_iban";

export type FieldDef = { key: FieldKey; required: boolean };

export type VatScheme = BusinessIdentity["vat_scheme"];
export const VAT_SCHEMES: readonly VatScheme[] = ["standard", "small_business", "exempt"];

/** Countries whose QR-bill takes a QR-IBAN (ADR-245). */
const QR_IBAN_COUNTRIES = ["CH", "LI"];

/** Values of the form, as text (empty = not filled). */
export type Draft = Partial<Record<FieldKey, string>>;

/** The required fields of a profile, one-of pairs as their first field. */
export function requiredFields(profile: Pick<CountryProfile, "required_fields">): Set<FieldKey> {
  return new Set(profile.required_fields.map((field) => field.split("_or_")[0] as FieldKey));
}

/** Which fields each row asks for, in the country of `profile`. */
export function groupFields(
  profile: Pick<CountryProfile, "country" | "required_fields" | "tax_office" | "tax_system">,
  vatScheme: VatScheme,
): Record<GroupKey, FieldDef[]> {
  const required = requiredFields(profile);
  const country = profile.country;
  const field = (key: FieldKey, always = false): FieldDef => ({ key, required: always || required.has(key) });
  const greek = country === "GR";
  // Greece: the VAT number is the ΑΦΜ with EL in front, filled in on save.
  const asksVatNumber = vatScheme === "standard" && profile.tax_system === "vat" && !greek;

  return {
    business: [
      field("legal_name"),
      field("trade_name"),
      field("tax_id"),
      ...(profile.tax_office ? [field("tax_office")] : []),
    ],
    address: [
      field("street"),
      field("postal_code"),
      field("city"),
      ...(country === "US" ? [field("region")] : []),
    ],
    tax: [
      field("vat_scheme", true),
      ...(asksVatNumber ? [field("vat_number")] : []),
      field("registration_number"),
      field("activity_code"),
      ...(greek ? [field("branch_code")] : []),
      field("iban"),
      ...(QR_IBAN_COUNTRIES.includes(country) ? [field("qr_iban")] : []),
    ],
  };
}

/** The row a missing field (as the API names it, `a_or_b` too) belongs to. */
export function groupOfMissing(missing: string): GroupKey | null {
  const first = missing.split("_or_")[0];
  if (["legal_name", "trade_name", "tax_id", "tax_office"].includes(first)) return "business";
  if (["street", "postal_code", "city", "region", "building_number"].includes(first)) return "address";
  if (first === "country_code") return null;
  return "tax";
}

/** Rows with nothing missing. A row is never done before the country is saved. */
export function doneGroups(status: Pick<IdentityStatus, "identity" | "missing">): Set<GroupKey> {
  if (!status.identity) return new Set();
  const open = new Set(status.missing.map(groupOfMissing).filter(Boolean));
  return new Set(GROUPS.filter((group) => !open.has(group)));
}

/** Share of the four rows that are done, 0–100. */
export function progress(status: Pick<IdentityStatus, "identity" | "missing">): number {
  const rows = 1 + GROUPS.length;
  const done = (status.identity ? 1 : 0) + doneGroups(status).size;
  return Math.round((100 * done) / rows);
}

export function draftOf(identity: BusinessIdentity | null): Draft {
  const draft: Draft = {};
  if (!identity) return draft;
  for (const key of Object.keys(identity) as Array<keyof BusinessIdentity>) {
    const value = identity[key];
    if (value === null || value === undefined) continue;
    draft[key as FieldKey] = String(value);
  }
  return draft;
}

/** The changes a row's form sends: empty text is cleared (null). */
export function changesFor(fields: FieldDef[], draft: Draft, country: string): IdentityChanges {
  const changes: Record<string, unknown> = {};
  for (const { key } of fields) {
    const value = (draft[key] ?? "").trim();
    if (key === "branch_code") changes[key] = value === "" ? 0 : Number(value);
    else if (key === "vat_scheme") changes[key] = value || "standard";
    else changes[key] = value === "" ? null : value;
  }
  // Greece: a VAT-registered business's VAT number is EL + ΑΦΜ.
  if (country === "GR" && "vat_scheme" in changes) {
    const afm = (draft.tax_id ?? "").trim();
    changes.vat_number = changes.vat_scheme === "standard" && afm ? `EL${afm}` : null;
  }
  return changes as IdentityChanges;
}

/** What a done row shows: its first three required values. */
export function summaryValues(fields: FieldDef[], draft: Draft): string[] {
  return fields
    .filter((field) => field.required && field.key !== "vat_scheme")
    .map((field) => (draft[field.key] ?? "").trim())
    .filter(Boolean)
    .slice(0, 3);
}

/** The country's own name for a field, printed after the translated label. */
const LOCAL_TERMS: Partial<Record<string, Partial<Record<FieldKey, string>>>> = {
  GR: { tax_id: "ΑΦΜ", tax_office: "ΔΟΥ", registration_number: "ΓΕΜΗ", activity_code: "ΚΑΔ" },
  CY: { tax_id: "TIC" },
  DE: { tax_id: "Steuernummer", vat_number: "USt-IdNr.", registration_number: "Handelsregister", activity_code: "WZ" },
  AT: { tax_id: "Steuernummer", vat_number: "UID", registration_number: "Firmenbuch" },
  CH: { tax_id: "UID", vat_number: "MWST", registration_number: "UID" },
  LI: { vat_number: "MWST" },
  FR: { registration_number: "SIREN / SIRET", vat_number: "TVA", activity_code: "NAF" },
  MC: { registration_number: "RCI", vat_number: "TVA", activity_code: "NAF" },
  BE: { tax_id: "BCE / KBO", vat_number: "TVA / BTW" },
  LU: { registration_number: "RCS", vat_number: "TVA" },
  GB: { tax_id: "UTR", registration_number: "Companies House" },
  US: { tax_id: "EIN" },
};

export function localTerm(country: string, field: FieldKey): string | null {
  return LOCAL_TERMS[country]?.[field] ?? null;
}

/**
 * The Greek ΑΦΜ's check digit (ADR-265): nine digits, the first eight
 * weighted by 2⁸…2¹, the sum mod 11 mod 10 is the ninth. The look-up is
 * offered only for a number that passes, so a typo never reaches AADE.
 */
export function isValidAfm(value: string): boolean {
  const afm = value.trim();
  if (!/^\d{9}$/.test(afm) || afm === "000000000") return false;
  let sum = 0;
  for (let index = 0; index < 8; index += 1) sum += Number(afm[index]) * 2 ** (8 - index);
  return (sum % 11) % 10 === Number(afm[8]);
}

/** What AADE's registry answers (only the fields the details use). */
export type RegistryDetails = {
  legal_name?: string | null;
  trade_name?: string | null;
  tax_office?: string | null;
  street?: string | null;
  building_number?: string | null;
  postal_code?: string | null;
  city?: string | null;
  activity_code?: string | null;
};

/**
 * «Συμπλήρωση από το ΑΦΜ»: `shown` fills the business row's own fields (staff
 * check them before saving); `later` holds the address and ΚΑΔ, saved with
 * the row only where the details have nothing yet, so typed values stay.
 */
export type RegistryLater = Partial<Record<"street" | "postal_code" | "city" | "activity_code", string>>;

export function fromRegistry(business: RegistryDetails, current: Draft): { shown: Draft; later: RegistryLater } {
  const text = (value: string | null | undefined) => (typeof value === "string" ? value.trim() : "");
  const shown: Draft = {};
  for (const key of ["legal_name", "trade_name", "tax_office"] as const) {
    if (text(business[key])) shown[key] = text(business[key]);
  }
  const found: Required<RegistryLater> = {
    street: [text(business.street), text(business.building_number)].filter(Boolean).join(" "),
    postal_code: text(business.postal_code),
    city: text(business.city),
    activity_code: text(business.activity_code),
  };
  const later: RegistryLater = {};
  for (const [key, value] of Object.entries(found) as Array<[keyof RegistryLater, string]>) {
    if (value && !(current[key] ?? "").trim()) later[key] = value;
  }
  return { shown, later };
}
