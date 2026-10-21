"use client";

import { useId, useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { suggestMediaAltText, updateMediaAltText } from "@/api/media";
import { clientErrorMessage } from "@/components/client/errors";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

/** Once the server said suggestions are off (503), the button stays hidden for this visit. */
let suggestionsUnavailable = false;

/**
 * «Περιγραφή» of one photo (ADR-157 §6): optional text up to 500 characters,
 * saved with PATCH. «Πρότεινε περιγραφή» asks for a one-sentence suggestion
 * that is shown, and used only when tapped.
 */
export function AltTextSheet({
  mediaId,
  previewUrl,
  initial,
  maxLength,
  onSaved,
  onClose,
}: {
  mediaId: string;
  previewUrl: string;
  initial: string;
  maxLength: number;
  onSaved: (altText: string) => void;
  onClose: () => void;
}) {
  const t = useTranslations("Media");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const labelId = useId();
  const fieldId = useId();
  const [text, setText] = useState(initial);
  const [suggestion, setSuggestion] = useState<string | null>(null);
  const [suggesting, setSuggesting] = useState(false);
  const [canSuggest, setCanSuggest] = useState(!suggestionsUnavailable);
  const [note, setNote] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function suggest() {
    if (!tokens || suggesting) return;
    setSuggesting(true);
    setNote(null);
    try {
      setSuggestion(await suggestMediaAltText(tokens.access_token, mediaId, locale));
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 503) {
        suggestionsUnavailable = true;
        setCanSuggest(false);
        setNote(t("altSuggestUnavailable"));
      } else if (caught instanceof ApiError && caught.status === 409) {
        setNote(t("altSuggestNotReady"));
      } else {
        setNote(clientErrorMessage(caught, tUi));
      }
    } finally {
      setSuggesting(false);
    }
  }

  async function save() {
    if (!tokens || saving) return;
    setSaving(true);
    setError(null);
    const value = text.trim();
    try {
      await updateMediaAltText(tokens.access_token, mediaId, value || null);
      onSaved(value);
      onClose();
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
      setSaving(false);
    }
  }

  return (
    <Sheet
      labelId={labelId}
      title={t("altTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary disabled={saving || text.length > maxLength} onClick={() => void save()}>
            {saving ? t("altSaving") : t("altSave")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        <div className="flex items-start gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element -- a local object URL */}
          <img src={previewUrl} alt="" className="h-20 w-20 shrink-0 rounded-2xl object-cover" />
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("altHint")}</p>
        </div>
        <label htmlFor={fieldId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("altText")}
        </label>
        <textarea
          id={fieldId}
          value={text}
          maxLength={maxLength}
          rows={4}
          onChange={(event) => setText(event.target.value)}
          placeholder={t("altPlaceholder")}
          aria-describedby={`${fieldId}-count`}
          className="rounded-2xl p-3 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <p id={`${fieldId}-count`} className="self-end text-xs tabular-nums" style={{ color: "var(--dim)" }}>
          {t("altCount", { count: text.length, max: maxLength })}
        </p>
        {suggestion ? (
          <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
            <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("altSuggestion")}</p>
            <p className="text-sm" style={{ color: "var(--text)" }} data-testid="alt-suggestion">{suggestion}</p>
            <button
              type="button"
              onClick={() => setText(suggestion.slice(0, maxLength))}
              className="min-h-11 self-start rounded-full px-4 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("altUseSuggestion")}
            </button>
          </div>
        ) : canSuggest ? (
          <button
            type="button"
            onClick={() => void suggest()}
            disabled={suggesting}
            className="min-h-11 self-start rounded-full px-4 text-sm font-semibold disabled:opacity-60"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {suggesting ? t("altSuggesting") : t("altSuggest")}
          </button>
        ) : null}
        {note ? (
          <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>{note}</p>
        ) : null}
        <ErrorLine message={error} />
      </div>
    </Sheet>
  );
}
