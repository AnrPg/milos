/** The API accepts up to five weekly rest days (UserGamificationPreferences). */
export const MAX_OFF_DAYS = 5;

/** Toggle a weekday (0 = Sunday) in the rest-day set, never past the limit. */
export function toggleOffDay(days: number[], dow: number): number[] {
  if (days.includes(dow)) return days.filter((day) => day !== dow);
  if (days.length >= MAX_OFF_DAYS) return days;
  return [...days, dow].sort((a, b) => a - b);
}
