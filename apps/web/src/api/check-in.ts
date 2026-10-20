import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * QR check-in and Wallet (ADR-155, P2-M7, board 10): the door display and its
 * printed poster, the member's door scan, the personal code with Wallet, the
 * desk scan, the owner's rules and Εγώ › Συνδεδεμένες συσκευές.
 *
 * Staff calls go through the selected gym (`/admin`, tenant-prefixed by the
 * client). The member's own code lives under a gym too, but `/me/...` is
 * personal by default, so those paths name the gym explicitly.
 */
type Schemas = components["schemas"];

export type DoorDisplay = Schemas["CheckInDoorDisplay"];
export type DoorCode = DoorDisplay["codes"][number];
export type Poster = Schemas["CheckInPoster"];
export type CheckInRules = Schemas["CheckInRules"];
export type MemberCodeMode = NonNullable<CheckInRules["member_code_mode"]>;
export type ScanResult = Schemas["CheckInScanResult"];
export type ScanOutcome = ScanResult["outcome"];
export type ScanRequest = Schemas["CheckInScanRequest"];
export type UndoResult = Schemas["CheckInUndoResult"];
export type CheckInPackage = NonNullable<ScanResult["package"]>;
export type CheckInClass = Schemas["CheckInClass"];
export type CheckInBooking = Schemas["CheckInBooking"];
export type DeskResult = Schemas["CheckInDeskResult"];
export type DeskProblem = DeskResult["problems"][number];
export type DeskRequest = Schemas["CheckInDeskRequest"];
export type Visitor = Schemas["CheckInVisitors"]["visitors"][number];
export type MemberCode = Schemas["CheckInMemberCode"];
export type MemberCodeRevoked = Schemas["CheckInMemberCodeRevoked"];
export type WalletPlatform = Schemas["WalletAddRequest"]["platform"];
export type WalletAddResult = Schemas["WalletAddResult"];
export type WalletPass = Schemas["WalletPass"];
export type ConnectedDevices = Schemas["ConnectedDevices"];
export type Integration = ConnectedDevices["integrations"][number];

export const CHECK_IN_RULES_KEY = ["admin", "check-in", "settings"] as const;
export const doorKey = (locationId: string) => ["admin", "check-in", "door", locationId] as const;
export const posterKey = (locationId: string) => ["admin", "check-in", "poster", locationId] as const;
export const VISITORS_KEY = ["admin", "check-in", "visitors"] as const;
export const myCodeKey = (slug: string) => ["check-in", "my-code", slug] as const;
export const CONNECTED_DEVICES_KEY = ["me", "connected-devices"] as const;

const door = (locationId: string) => `/admin/check-in/door/${encodeURIComponent(locationId)}`;
const myGym = (slug: string) => `/org/${encodeURIComponent(slug)}/me`;

// Staff: the door and the poster ------------------------------------------------

export function fetchDoorDisplay(token: string, locationId: string, signal?: AbortSignal) {
  return apiRequest<DoorDisplay>(door(locationId), { token, signal });
}

/** «Νέος κωδικός πόρτας»: replaces the seed, so every code shown so far stops working. */
export function rotateDoor(token: string, locationId: string) {
  return apiRequest<DoorDisplay>(`${door(locationId)}/rotate`, { method: "POST", token });
}

export function fetchPoster(token: string, locationId: string) {
  return apiRequest<Poster>(`${door(locationId)}/poster`, { token });
}

export function setPosterEnabled(token: string, locationId: string, enabled: boolean) {
  return apiRequest<Poster>(`${door(locationId)}/poster`, { method: "PUT", token, body: { enabled } });
}

export function rotatePoster(token: string, locationId: string) {
  return apiRequest<Poster>(`${door(locationId)}/poster/rotate`, { method: "POST", token });
}

// Staff: rules, desk and visitors ------------------------------------------------

export async function fetchCheckInRules(token: string) {
  const data = await apiRequest<Schemas["CheckInRulesResponse"]>("/admin/check-in/settings", { token });
  return data.settings;
}

export async function updateCheckInRules(token: string, rules: CheckInRules) {
  const data = await apiRequest<Schemas["CheckInRulesResponse"]>("/admin/check-in/settings", {
    method: "PUT",
    token,
    body: rules,
  });
  return data.settings;
}

export function scanMemberCode(token: string, body: Schemas["CheckInDeskScanRequest"]) {
  return apiRequest<DeskResult>("/admin/check-in/scan-member", { method: "POST", token, body });
}

export function deskCheckIn(token: string, userId: string, body: DeskRequest) {
  return apiRequest<DeskResult>(`/admin/check-in/members/${encodeURIComponent(userId)}`, {
    method: "POST",
    token,
    body,
  });
}

/** Staff revoke a member's personal code (and the Wallet cards that carry it). */
export function revokeMemberCode(token: string, userId: string) {
  return apiRequest<MemberCodeRevoked>(`/admin/check-in/members/${encodeURIComponent(userId)}/code`, {
    method: "DELETE",
    token,
  });
}

export async function fetchVisitors(token: string, filters: { date?: string; locationId?: string } = {}) {
  const search = new URLSearchParams();
  if (filters.date) search.set("date", filters.date);
  if (filters.locationId) search.set("location_id", filters.locationId);
  const query = search.toString();
  const data = await apiRequest<Schemas["CheckInVisitors"]>(`/admin/check-in/visitors${query ? `?${query}` : ""}`, {
    token,
  });
  return data.visitors;
}

// Member: the door scan -----------------------------------------------------------

export function scanDoor(token: string, body: ScanRequest) {
  return apiRequest<ScanResult>("/check-in/scan", { method: "POST", token, body });
}

export function undoScan(token: string, undoToken: string) {
  return apiRequest<UndoResult>(`/check-in/scan/${encodeURIComponent(undoToken)}`, { method: "DELETE", token });
}

// Member: the personal code and Wallet ---------------------------------------------

export function fetchMyCode(token: string, slug: string) {
  return apiRequest<MemberCode>(`${myGym(slug)}/check-in/code`, { token });
}

/** «Νέος κωδικός»: the old code and every Wallet card carrying it stop working. */
export function resetMyCode(token: string, slug: string) {
  return apiRequest<MemberCode>(`${myGym(slug)}/check-in/code/reset`, { method: "POST", token });
}

export function addWalletPass(token: string, slug: string, platform: WalletPlatform) {
  return apiRequest<WalletAddResult>(`${myGym(slug)}/wallet-passes`, { method: "POST", token, body: { platform } });
}

// Εγώ › Συνδεδεμένες συσκευές ---------------------------------------------------------

export function fetchConnectedDevices(token: string) {
  return apiRequest<ConnectedDevices>("/me/connected-devices", { token });
}

/** Revoking a card resets the code it carries for that box (ADR-155 §10). */
export async function revokeWalletPass(token: string, id: string) {
  const data = await apiRequest<Schemas["WalletPassResponse"]>(`/me/wallet-passes/${encodeURIComponent(id)}`, {
    method: "DELETE",
    token,
  });
  return data.pass;
}
