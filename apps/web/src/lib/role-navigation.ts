// What each role sees in the top bar and in a page's tabs (ADR-103,
// docs/architecture/navigation-by-role.md). Staff links follow the
// membership's capabilities (ADR-099), so roles held together merge by union
// and whatever a gym unlocks for front desk shows up without extra rules.

import type { ClientFeature } from "@/components/client/entitlement";

export type NavItem = {
  id: string;
  href: string;
  labelKey: string;
  /** Path prefixes that make this link the active one; the longest match wins. */
  match: string[];
  /** Exact-match only (home links). */
  exact?: boolean;
  /** Staff links live under /org/:slug. */
  scoped?: boolean;
};

export type MembershipLike = {
  role: string;
  roles?: string[] | null;
  capabilities?: Record<string, string> | null;
};

export type View = "staff" | "client";

export const STAFF_ROLES = ["owner", "admin", "coach", "front_desk", "accountant", "janitor"] as const;
export const CLIENT_ROLES = ["member", "athlete"] as const;

export function membershipRoles(membership: MembershipLike | null | undefined): string[] {
  if (!membership) return [];
  const roles = membership.roles && membership.roles.length > 0 ? membership.roles : [membership.role];
  return Array.from(new Set(roles));
}

export function hasStaffRole(membership: MembershipLike | null | undefined) {
  return membershipRoles(membership).some((role) => (STAFF_ROLES as readonly string[]).includes(role));
}

/** The client role a membership also holds: athlete wins over member. */
export function clientRole(membership: MembershipLike | null | undefined): "member" | "athlete" | null {
  const roles = membershipRoles(membership);
  if (roles.includes("athlete")) return "athlete";
  if (roles.includes("member")) return "member";
  return null;
}

/** "admin" (any staff surface) or the client surface, honouring "My training". */
export function surfaceRole(
  membership: MembershipLike | null | undefined,
  view: View = "staff",
): "admin" | "member" | "athlete" {
  const client = clientRole(membership);
  // A janitor who also trains keeps the client pages; the cleaning log is a
  // link in that bar (navigation-by-role.md §2).
  const staff = membershipRoles(membership).filter((role) => (STAFF_ROLES as readonly string[]).includes(role));
  if (client && staff.length > 0 && staff.every((role) => role === "janitor")) return client;
  if (hasStaffRole(membership) && !(view === "client" && client)) return "admin";
  return client ?? "member";
}

export function can(membership: MembershipLike | null | undefined, capability: string) {
  return Boolean(membership?.capabilities?.[capability]);
}

const COACHING_PATHS = [
  "/admin/class-schedule",
  "/admin/coaching-assignments",
  "/admin/workouts",
  "/admin/schedule",
  "/admin/check-in",
  "/admin/appointments",
];

/** Staff links in priority order; what does not fit moves into "More". */
export function staffNavItems(membership: MembershipLike | null | undefined): NavItem[] {
  const has = (capability: string) => can(membership, capability);
  const coaching = has("manage_coaching") || has("manage_workouts");
  const users = has("grant_staff_roles");
  const items: NavItem[] = [];

  // A janitor also reports inventory (ADR-104); that alone does not earn a Home link.
  const onlyCleaning =
    has("record_cleaning") &&
    Object.keys(membership?.capabilities ?? {}).every((capability) => capability === "record_cleaning" || capability === "report_inventory");

  if (!onlyCleaning) items.push({ id: "home", href: "/admin", labelKey: "home", match: ["/admin"], exact: true, scoped: true });
  if (coaching) {
    items.push({ id: "coaching", href: "/admin/class-schedule", labelKey: "coaching", match: COACHING_PATHS, scoped: true });
  } else {
    if (has("check_in")) items.push({ id: "checkIn", href: "/admin/check-in", labelKey: "checkIn", match: ["/admin/check-in"], scoped: true });
    if (has("run_classes")) items.push({ id: "classes", href: "/admin/class-schedule", labelKey: "classes", match: ["/admin/class-schedule", "/admin/appointments"], scoped: true });
  }
  if (has("take_payments")) items.push({ id: "finance", href: "/admin/finance", labelKey: "finance", match: ["/admin/finance"], scoped: true });
  if (users) {
    items.push({ id: "users", href: "/admin/users", labelKey: "users", match: ["/admin/users"], scoped: true });
  } else if (!coaching && (has("view_directory") || has("view_billing_contacts"))) {
    items.push({ id: "clients", href: "/admin/users", labelKey: "clients", match: ["/admin/users"], scoped: true });
  }
  if (!users && has("view_finance_reports")) {
    items.push({ id: "reports", href: "/admin/metrics/finance", labelKey: "reports", match: ["/admin/metrics/finance"], scoped: true });
  }
  if (has("record_cleaning") && !has("manage_cleaning_areas")) {
    items.push({ id: "cleaning", href: "/admin/cleaning", labelKey: "cleaningLog", match: ["/admin/cleaning"], scoped: true });
  }
  // ADR-104: front desk manages inventory from the bar (it lands in "More");
  // owners and admins reach it from a dashboard tile.
  if (has("manage_inventory") && !users) {
    items.push({ id: "inventory", href: "/admin/inventory", labelKey: "inventory", match: ["/admin/inventory"], scoped: true });
  }
  // ADR-143: coaches moderate the community from the bar ("More"); owners and
  // admins reach Κοινότητα from a dashboard tile and from settings.
  if (has("moderate_community") && !users) {
    items.push({ id: "community", href: "/admin/community", labelKey: "community", match: ["/admin/community"], scoped: true });
  }
  return items;
}

/**
 * The member app's four fixed tabs (redesign Phase 1, ADR-137; brief §6.1):
 * Αρχική · Box · Ημερολόγιο · Εγώ. Every member page lives under the tab
 * that is its home (lib/member-routes.ts lists the moves); workout pages
 * opened from Box stay at /workouts and are claimed by Box.
 */
export function clientNavItems(): NavItem[] {
  return [
    { id: "home", href: "/", labelKey: "home", match: ["/", "/feed", "/clubs", "/around", "/around/events", "/around/boxes", "/around/clubs", "/around/posts"], exact: true },
    {
      id: "box",
      href: "/box",
      labelKey: "box",
      match: ["/box", "/class-timer", "/workouts"],
    },
    {
      id: "journal",
      href: "/journal",
      labelKey: "journal",
      match: ["/journal"],
    },
    { id: "me", href: "/me", labelKey: "me", match: ["/me"] },
  ];
}

/** Staff links a client may also hold; they live in Εγώ, never in the bar (no "More"). */
export function clientExtraLinks(membership?: MembershipLike | null): NavItem[] {
  const items: NavItem[] = [];
  if (can(membership, "record_cleaning") && !can(membership, "manage_cleaning_areas") && !can(membership, "take_payments")) {
    items.push({ id: "cleaning", href: "/admin/cleaning", labelKey: "cleaningLog", match: ["/admin/cleaning"], scoped: true });
  }
  if (can(membership, "report_inventory") && !can(membership, "manage_inventory")) {
    items.push({ id: "inventory", href: "/admin/inventory", labelKey: "inventory", match: ["/admin/inventory"], scoped: true });
  }
  return items;
}

/** Full-screen pages where the bottom bar would get in the way. */
const BOTTOM_BAR_HIDDEN = [/^\/workouts\/[^/]+\/execute(?:\/|$)/, /^\/workouts\/free-text\/execute(?:\/|$)/, /^\/class-timer\/[^/]+\/(?:display|control)(?:\/|$)/, /^\/admin\/check-in\/(?:door|poster)\/[^/]+\/?$/];

export function showsBottomBar(pathname: string) {
  const path = relativePath(pathname);
  return !BOTTOM_BAR_HIDDEN.some((pattern) => pattern.test(path));
}

function relativePath(pathname: string) {
  return pathname.replace(/^\/org\/[^/]+(?=\/|$)/, "") || "/";
}

function matches(path: string, prefix: string, exact?: boolean) {
  if (exact || prefix === "/") return path === prefix;
  return path === prefix || path.startsWith(prefix + "/") || path.startsWith(prefix + "?");
}

/** The id of the link (or tab) that owns `pathname`: the longest matching prefix. */
export function activeItemId(pathname: string, items: Pick<NavItem, "id" | "match" | "exact">[]) {
  const path = relativePath(pathname);
  let best: { id: string; length: number } | null = null;
  for (const item of items) {
    for (const prefix of item.match) {
      if (matches(path, prefix, item.exact) && (!best || prefix.length > best.length)) {
        best = { id: item.id, length: prefix.length };
      }
    }
  }
  return best?.id ?? null;
}

export type SectionTab = { id: string; href: string; labelKey: string; match: string[]; scoped?: boolean };
export type SectionGroup = { id: string; tabs: SectionTab[] };

/** The tab strip of the page group `pathname` belongs to, if any. */
export function sectionGroupFor(
  pathname: string,
  context: {
    surface: "admin" | "member" | "athlete";
    staffItems: NavItem[];
    features: ClientFeature[];
    /** Ρυθμίσεις › Σώμα (ADR-158 §7): a section switched off loses its segment. */
    journalSections?: { body?: boolean; wellness?: boolean } | null;
  },
): SectionGroup | null {
  const path = relativePath(pathname);
  const groups: SectionGroup[] = [];
  // The Box hub carries its own action row (brief §7.4); the strip serves its sub-pages.
  if (context.surface !== "admin" && path === "/box") return null;

  if (context.surface === "admin") {
    if (context.staffItems.some((item) => item.id === "coaching")) {
      groups.push({
        id: "coaching",
        tabs: [
          { id: "gymClasses", href: "/admin/class-schedule", labelKey: "gymClasses", match: ["/admin/class-schedule", "/admin/schedule", "/admin/check-in", "/admin/appointments"], scoped: true },
          { id: "personalTraining", href: "/admin/coaching-assignments", labelKey: "personalTraining", match: ["/admin/coaching-assignments"], scoped: true },
          { id: "wodsVault", href: "/admin/workouts", labelKey: "wodsVault", match: ["/admin/workouts"], scoped: true },
        ],
      });
    }
  } else {
    const feature = (name: ClientFeature) => context.features.includes(name);
    // Box's sub-pages (brief §6.2): today, programmes, classes, then what the package unlocks.
    groups.push({
      id: "box",
      tabs: [
        { id: "boxToday", href: "/box", labelKey: "today", match: ["/box"] },
        // ADR-125: members receive personal workouts and class versions too.
        { id: "myWorkouts", href: "/box/workouts", labelKey: "myWorkouts", match: ["/box/workouts"] },
        { id: "classes", href: "/box/schedule", labelKey: "schedule", match: ["/box/schedule"] },
        ...(feature("appointments") ? [{ id: "appointments", href: "/box/appointments", labelKey: "appointments", match: ["/box/appointments"] }] : []),
        ...(feature("videos") ? [{ id: "videos", href: "/box/videos", labelKey: "videos", match: ["/box/videos"] }] : []),
        ...(feature("coaching") ? [{ id: "coaching", href: "/box/coach", labelKey: "coach", match: ["/box/coach"] }] : []),
      ],
    });
    // Journal segments in the map's order: Ροή · Vault · Σώμα · Ευεξία ·
    // Πρόοδος. Σώμα and Ευεξία leave when switched off in Ρυθμίσεις › Σώμα. Reviews are entries of Ροή; their form page lights Ροή.
    // Πρόοδος is for everyone (its advanced statistics stay package-gated
    // inside the page) and owns the full Pantheon page.
    groups.push({
      id: "journal",
      tabs: [
        { id: "flow", href: "/journal", labelKey: "journalFlow", match: ["/journal"] },
        { id: "vault", href: "/journal/vault", labelKey: "vault", match: ["/journal/vault"] },
        ...(context.journalSections?.body === false
          ? []
          : [{ id: "body", href: "/journal/body", labelKey: "body", match: ["/journal/body"] }]),
        ...(context.journalSections?.wellness === false
          ? []
          : [{ id: "wellbeing", href: "/journal/wellbeing", labelKey: "wellbeing", match: ["/journal/wellbeing"] }]),
        { id: "progress", href: "/journal/progress", labelKey: "progress", match: ["/journal/progress", "/journal/pantheon", "/journal/atlas"] },
      ],
    });
  }

  let best: { group: SectionGroup; length: number } | null = null;
  for (const group of groups) {
    for (const tab of group.tabs) {
      for (const prefix of tab.match) {
        if (matches(path, prefix) && (!best || prefix.length > best.length)) best = { group, length: prefix.length };
      }
    }
  }
  return best?.group ?? null;
}

/**
 * ADR-177: the screens a role most likely opens next, preloaded once the app
 * is idle so a tap renders without a server round trip. Bar links first, then
 * the sub-pages each role opens most; never fewer than six where the role has
 * that many pages.
 */
export function likelyScreens(surface: "admin" | "member" | "athlete", staffItems: NavItem[]): NavItem[] {
  const screens =
    surface === "admin"
      ? [
          ...staffItems,
          ...(staffItems.some((item) => item.id === "coaching")
            ? [
                { id: "personalTraining", href: "/admin/coaching-assignments", labelKey: "personalTraining", match: [], scoped: true },
                { id: "wodsVault", href: "/admin/workouts", labelKey: "wodsVault", match: [], scoped: true },
              ]
            : []),
          ...(staffItems.some((item) => item.id === "users")
            ? [{ id: "settings", href: "/admin/settings", labelKey: "settings", match: [], scoped: true }]
            : []),
        ]
      : [
          ...clientNavItems(),
          { id: "myWorkouts", href: "/box/workouts", labelKey: "myWorkouts", match: [] },
          { id: "classes", href: "/box/schedule", labelKey: "schedule", match: [] },
          { id: "progress", href: "/journal/progress", labelKey: "progress", match: [] },
          { id: "settings", href: "/me/settings", labelKey: "settings", match: [] },
        ];
  return [...new Map(screens.map((item) => [item.href, item])).values()];
}
