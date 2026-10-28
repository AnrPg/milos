import { create } from "zustand";

import { formatLocalIsoDate, parseLocalDate, type ScheduleDays } from "@/components/schedule/calendar-window";

type ScheduleStore = {
  classTypeIds: string[];
  days: ScheduleDays;
  startDate: string;
  setClassTypeIds: (value: string[]) => void;
  setDays: (value: ScheduleDays) => void;
  /** The day view of one date (a month cell's date or its "+N more"). */
  openDay: (isoDate: string) => void;
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
  classTypeIds: [],
  days: 3,
  startDate: todayIso(),
  setClassTypeIds: (classTypeIds) => set({ classTypeIds }),
  setDays: (days) => set({ days }),
  openDay: (startDate) => set({ days: 1, startDate }),
  shiftWindow: (direction) => {
    const { days, startDate } = get();
    set({ startDate: days === 30 ? addMonths(startDate, direction) : addDays(startDate, days * direction) });
  },
  resetWindow: () => set({ startDate: todayIso() }),
}));
