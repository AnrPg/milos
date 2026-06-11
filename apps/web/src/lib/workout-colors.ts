export const WORKOUT_TYPE_COLORS: Record<string, string> = {
  crossfit:    "#c0392b",
  strength:    "#d95d39",
  gymnastics:  "#c97b4b",
  aerobics:    "#b5651d",
  flexibility: "#8b4513",
  recovery:    "#6b3a2a",
};

export function workoutTypeColor(type: string): string {
  return WORKOUT_TYPE_COLORS[type] ?? "#d95d39";
}
