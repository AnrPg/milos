import { currentLoginSession } from "@/lib/login-session";

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
    { id: "schedule", icon: "🗓️", href: "/box/schedule" },
    { id: "train", icon: "⏱️", href: "/workouts" },
    { id: "records", icon: "🏆", href: "/journal/progress#prs" },
    { id: "account", icon: "💳", href: "/me/payments" },
  ],
  athlete: [
    { id: "welcome", icon: "👋" },
    { id: "programme", icon: "📋", href: "/box/workouts" },
    { id: "train", icon: "⏱️" },
    { id: "records", icon: "🏆", href: "/journal/progress#prs" },
    { id: "account", icon: "💳", href: "/me/payments" },
  ],
};

export const checklistLaterKey = (slug: string) => ["palee", "onboarding-later", slug].join(":");

/**
 * The admin setup checklist pops up on every login until every step is done
 * or skipped. "Remind me later" snoozes it for the rest of this login only:
 * the snooze records the login it was made in, so the next sign-in shows the
 * checklist again even in the same tab.
 */
export function checklistSnoozed(slug: string) {
  const login = currentLoginSession();
  return login !== null && readStorage("local", checklistLaterKey(slug)) === login;
}

export function snoozeChecklist(slug: string) {
  const login = currentLoginSession();
  if (login) writeStorage("local", checklistLaterKey(slug), login);
}

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
