/**
 * The ten general physical skills used by WOD goals and the qualities radar
 * (ADR-163), mirroring `Palee.Anatomy.Domain.FitnessQualities`.
 * Labels: `Anatomy.quality.<id>`.
 */
export const FITNESS_QUALITIES = [
  "cardiorespiratory-endurance",
  "stamina",
  "strength",
  "flexibility",
  "power",
  "speed",
  "coordination",
  "agility",
  "balance",
  "accuracy",
] as const;

export type FitnessQuality = (typeof FITNESS_QUALITIES)[number];
