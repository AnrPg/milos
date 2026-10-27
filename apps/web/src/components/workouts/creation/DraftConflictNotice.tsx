"use client";

import { useTranslations } from "next-intl";
import { useState } from "react";

/**
 * Shown above the editor when the draft was saved somewhere else after it was
 * opened here. Autosave is paused until the coach picks the version to keep.
 */
export function DraftConflictNotice({
  onKeepMine,
  onLoadSaved,
}: {
  onKeepMine: () => Promise<void>;
  onLoadSaved: () => Promise<void>;
}) {
  const t = useTranslations("DraftConflict");
  const [working, setWorking] = useState(false);
  const [failed, setFailed] = useState(false);

  async function run(action: () => Promise<void>) {
    setWorking(true);
    setFailed(false);
    try {
      await action();
    } catch {
      setFailed(true);
    } finally {
      setWorking(false);
    }
  }

  return (
    <div
      role="alert"
      data-testid="draft-conflict-notice"
      className="mx-4 mt-3 rounded-2xl px-4 py-3 text-sm"
      style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)", border: "1px solid var(--warning)", color: "var(--text)" }}
    >
      <p className="font-bold">{t("title")}</p>
      <p className="mt-1">{t("body")}</p>
      <p className="mt-2 font-semibold">{t("question")}</p>
      <div className="mt-2 grid gap-2 sm:grid-cols-2">
        <button
          type="button"
          disabled={working}
          onClick={() => void run(onKeepMine)}
          className="rounded-xl px-3 py-2 text-start disabled:opacity-60"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          <span className="block font-bold">{t("keepMine")}</span>
          <span className="block text-xs">{t("keepMineHint")}</span>
        </button>
        <button
          type="button"
          disabled={working}
          onClick={() => void run(onLoadSaved)}
          className="rounded-xl border px-3 py-2 text-start disabled:opacity-60"
          style={{ background: "var(--card)", borderColor: "var(--border-strong)", color: "var(--text)" }}
        >
          <span className="block font-bold">{t("loadSaved")}</span>
          <span className="block text-xs" style={{ color: "var(--muted)" }}>{t("loadSavedHint")}</span>
        </button>
      </div>
      {working ? <p className="mt-2 text-xs" role="status">{t("working")}</p> : null}
      {failed ? <p className="mt-2 text-xs font-semibold" style={{ color: "var(--danger)" }}>{t("failed")}</p> : null}
    </div>
  );
}
