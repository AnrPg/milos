// ADR-256: what may be bought where. Physical services and goods of the box
// are paid through the box's own provider everywhere (Apple 3.1.3(e), Google
// Play Payments policy). Digital-only services are not sold inside the store
// apps at all, and neither is the Plan (Palee): the web stays unchanged.
import type { NativePlatform } from "./index";

/** A subscription package's settings (the `fields` of a package contract, ADR-098). */
export type PackageFields = Record<string, unknown>;

export type Sellable =
  | { kind: "subscription_package"; fields: PackageFields }
  | { kind: "class_booking" }
  | { kind: "personal_training" }
  | { kind: "event_ticket" }
  | { kind: "shop_order" }
  | { kind: "invoice" }
  | { kind: "palee_plan" };

function on(fields: PackageFields, key: string) {
  return fields[key] === true;
}

function positive(value: unknown) {
  return typeof value === "number" && value > 0;
}

/**
 * True when the package includes something used in person at the box:
 * classes, personal training or assessments, open gym, or events. A package
 * with only Online programming, on-demand content or a nutrition plan is
 * digital-only.
 */
export function hasPhysicalService(fields: PackageFields): boolean {
  return (
    on(fields, "group_classes.included") ||
    on(fields, "personal_training.included") ||
    positive(fields["personal_training.assessments"]) ||
    on(fields, "facility.open_gym") ||
    on(fields, "perks.events")
  );
}

/** Whether this screen may offer to buy the item: always on the web, by store rules in the apps. */
export function canBuyHere(item: Sellable, platform: NativePlatform | null): boolean {
  if (!platform) return true;
  switch (item.kind) {
    case "palee_plan":
      return false;
    case "subscription_package":
      return hasPhysicalService(item.fields);
    default:
      return true;
  }
}
