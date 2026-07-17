"use client";

type MessageComposerProps = {
  value: string;
  onChange: (value: string) => void;
  onSend: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  placeholder: string;
  sendLabel: string;
  sendingLabel?: string;
  sending?: boolean;
  error?: string | null;
};

export function MessageComposer({
  value,
  onChange,
  onSend,
  onFocus,
  onBlur,
  placeholder,
  sendLabel,
  sendingLabel,
  sending = false,
  error,
}: MessageComposerProps) {
  const sendDisabled = !value.trim() || sending;

  return (
    <div>
      {error ? (
        <p className="mb-2 whitespace-pre-wrap text-xs" role="alert" style={{ color: "var(--danger)" }}>
          {error}
        </p>
      ) : null}
      <div className="flex items-end gap-2">
        <textarea
          className="min-h-20 max-h-48 flex-1 resize-y rounded-[1rem] px-3 py-2 text-sm leading-5 outline-none"
          style={{
            background: "var(--card)",
            color: "var(--text)",
            border: "1px solid var(--border-strong)",
          }}
          placeholder={placeholder}
          rows={3}
          value={value}
          onBlur={onBlur}
          onChange={(event) => onChange(event.target.value)}
          onFocus={onFocus}
        />
        <button
          type="button"
          onClick={onSend}
          disabled={sendDisabled}
          className="rounded-full px-3 py-2 text-xs font-semibold"
          style={{
            background: "var(--primary)",
            color: "var(--primary-contrast)",
            opacity: sendDisabled ? 0.4 : 1,
          }}
        >
          {sending && sendingLabel ? sendingLabel : sendLabel}
        </button>
      </div>
    </div>
  );
}
