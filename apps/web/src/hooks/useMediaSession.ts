"use client";

import { useEffect, useRef } from "react";

type MediaSessionState = {
  /** e.g. "Work 3/8 · 0:14" */
  title: string;
  /** e.g. the section or workout name */
  subtitle: string;
  running: boolean;
  onPlay: () => void;
  onPause: () => void;
};

/**
 * Mirrors the timer on the lock screen and in system media controls where the
 * browser supports the Media Session API. Browsers only surface it while the
 * page holds an audio focus (our cues), so this is best effort.
 */
export function useMediaSession({ title, subtitle, running, onPlay, onPause }: MediaSessionState) {
  const handlers = useRef({ onPlay, onPause });
  useEffect(() => {
    handlers.current = { onPlay, onPause };
  }, [onPause, onPlay]);

  useEffect(() => {
    if (typeof navigator === "undefined" || !("mediaSession" in navigator)) return;
    const session = navigator.mediaSession;
    try {
      session.metadata = new MediaMetadata({ title, artist: subtitle, album: "Milos" });
      session.playbackState = running ? "playing" : "paused";
    } catch {
      // MediaMetadata is missing in some embedded browsers.
    }
  }, [running, subtitle, title]);

  useEffect(() => {
    if (typeof navigator === "undefined" || !("mediaSession" in navigator)) return;
    const session = navigator.mediaSession;
    const set = (action: MediaSessionAction, handler: MediaSessionActionHandler | null) => {
      try {
        session.setActionHandler(action, handler);
      } catch {
        // Unsupported action.
      }
    };
    set("play", () => handlers.current.onPlay());
    set("pause", () => handlers.current.onPause());
    return () => {
      set("play", null);
      set("pause", null);
      try {
        session.metadata = null;
        session.playbackState = "none";
      } catch {
        // ignore
      }
    };
  }, []);
}
