import { create } from "zustand";

import type { TrainingType } from "@/api/schedule";
import { formatLocalIsoDate, parseLocalDate } from "@/components/schedule/calendar-window";

type ScheduleStore = {
  trainingType: TrainingType | null;
  days: 3 | 7 | 30;
  startDate: string;
  setTrainingType: (value: TrainingType | null) => void;
  setDays: (value: 3 | 7 | 30) => void;
  shiftWindow: (direction: -1 | 1) => void;
  resetWindow: () => void;
};

function todayIso() {
  return formatLocalIsoDate(new Date());
}

function addDays(isoDate: string, days: number) {
  const date = parseLocalDate(isoDate);
  date.setDate(date.getDate() + days);
  return formatLocalIsoDate(date);
}

function addMonths(isoDate: string, months: number) {
  const date = parseLocalDate(isoDate);
  date.setMonth(date.getMonth() + months);
  return formatLocalIsoDate(date);
}

export const useScheduleStore = create<ScheduleStore>((set, get) => ({
  trainingType: null,
  days: 3,
  startDate: todayIso(),
  setTrainingType: (trainingType) => set({ trainingType }),
  setDays: (days) => set({ days }),
  shiftWindow: (direction) => {
    const { days, startDate } = get();
    set({ startDate: days === 30 ? addMonths(startDate, direction) : addDays(startDate, days * direction) });
  },
  resetWindow: () => set({ startDate: todayIso() }),
}));
