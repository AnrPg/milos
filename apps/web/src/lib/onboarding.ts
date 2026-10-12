export type TourAudience = "admin" | "member" | "athlete";
export type TourStep = { id: string; icon: string; href?: string };

/** Short tours (3–6 steps) per role; copy lives in messages under Onboarding.tour.<audience>.<id>. */
export const TOUR_STEPS: Record<TourAudience, TourStep[]> = {
  admin: [
    { id: "welcome", icon: "👋" },
    { id: "dashboard", icon: "📊", href: "/admin" },
    { id: "classes", icon: "🗓️", href: "/admin/class-schedule" },
    { id: "workouts", icon: "✍️", href: "/admin/workouts/new" },
    { id: "people", icon: "👥", href: "/admin/users" },
    { id: "config", icon: "⚙️", href: "/admin/settings" },
  ],
  member: [
    { id: "welcome", icon: "👋" },
    { id: "schedule", icon: "🗓️", href: "/schedule" },
    { id: "train", icon: "⏱️", href: "/workouts" },
    { id: "records", icon: "🏆", href: "/my-workouts/pantheon" },
    { id: "account", icon: "💳", href: "/account/billing" },
  ],
  athlete: [
    { id: "welcome", icon: "👋" },
    { id: "programme", icon: "📋", href: "/my-workouts" },
    { id: "train", icon: "⏱️" },
    { id: "records", icon: "🏆", href: "/my-workouts/pantheon" },
    { id: "account", icon: "💳", href: "/account/billing" },
  ],
};

export const checklistLaterKey = (slug: string) => ["milos", "onboarding-later", slug].join(":");

type StorageKind = "local" | "session";

function storage(kind: StorageKind) {
  return kind === "local" ? window.localStorage : window.sessionStorage;
}

/** Storage can be unavailable (private mode, blocked site data); never throw. */
export function readStorage(kind: StorageKind, key: string) {
  try {
    return storage(kind).getItem(key);
  } catch {
    return null;
  }
}

export function writeStorage(kind: StorageKind, key: string, value: string) {
  try {
    storage(kind).setItem(key, value);
  } catch {}
}
