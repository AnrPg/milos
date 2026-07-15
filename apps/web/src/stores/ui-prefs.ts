import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

interface UiPrefsState {
  // string[] per userId — JSON-serializable for localStorage
  hiddenThreadIdsByUser: Record<string, string[]>;
  hideThread: (userId: string, threadId: string) => void;
  isThreadHidden: (userId: string, threadId: string) => boolean;
}

export const useUiPrefs = create<UiPrefsState>()(
  persist(
    (set, get) => ({
      hiddenThreadIdsByUser: {},

      hideThread: (userId, threadId) => {
        set((state) => {
          const existing = state.hiddenThreadIdsByUser[userId] ?? [];
          if (existing.includes(threadId)) return state;
          return {
            hiddenThreadIdsByUser: {
              ...state.hiddenThreadIdsByUser,
              [userId]: [...existing, threadId],
            },
          };
        });
      },

      isThreadHidden: (userId, threadId) => {
        const ids = get().hiddenThreadIdsByUser[userId] ?? [];
        return ids.includes(threadId);
      },
    }),
    {
      name: "milos-ui-prefs",
      storage: createJSONStorage(() => localStorage),
    },
  ),
);
