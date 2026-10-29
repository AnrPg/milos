"use client";

import { useEffect, useRef, useState, type PointerEvent } from "react";
import { useTranslations } from "next-intl";

import { PAD_HEIGHT, PAD_WIDTH, normalizeStrokes } from "./documents-model";

/**
 * «Πάτα για υπογραφή με το δάχτυλο» (mockup s7): a box the client signs in
 * with a finger or a mouse. It keeps the strokes as points in a fixed
 * 600×200 box, which is what the API stores and redraws in the PDF
 * (ADR-252 §3: vector strokes, never an image). Colours come from the theme.
 */
export function SignaturePad({ onChange, disabled }: { onChange: (strokes: number[][][]) => void; disabled?: boolean }) {
  const t = useTranslations("Documents");
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const strokesRef = useRef<number[][][]>([]);
  const drawing = useRef(false);
  const [empty, setEmpty] = useState(true);

  useEffect(() => {
    redraw();
  });

  function point(event: PointerEvent<HTMLCanvasElement>) {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / Math.max(1, rect.width)) * PAD_WIDTH;
    const y = ((event.clientY - rect.top) / Math.max(1, rect.height)) * PAD_HEIGHT;
    return [x, y];
  }

  function redraw() {
    const canvas = canvasRef.current;
    const context = canvas?.getContext?.("2d");
    if (!canvas || !context) return;
    context.clearRect(0, 0, PAD_WIDTH, PAD_HEIGHT);
    context.lineWidth = 3;
    context.lineCap = "round";
    context.lineJoin = "round";
    context.strokeStyle = getComputedStyle(canvas).color || "currentColor";
    for (const stroke of strokesRef.current) {
      context.beginPath();
      stroke.forEach(([x, y], index) => (index === 0 ? context.moveTo(x, y) : context.lineTo(x, y)));
      if (stroke.length === 1) context.lineTo(stroke[0][0] + 0.5, stroke[0][1] + 0.5);
      context.stroke();
    }
  }

  function publish() {
    const strokes = normalizeStrokes(strokesRef.current);
    setEmpty(strokes.length === 0);
    onChange(strokes);
  }

  function start(event: PointerEvent<HTMLCanvasElement>) {
    if (disabled) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture?.(event.pointerId);
    drawing.current = true;
    strokesRef.current = [...strokesRef.current, [point(event)]];
    redraw();
  }

  function move(event: PointerEvent<HTMLCanvasElement>) {
    if (!drawing.current) return;
    const strokes = strokesRef.current;
    strokes[strokes.length - 1].push(point(event));
    redraw();
  }

  function end() {
    if (!drawing.current) return;
    drawing.current = false;
    publish();
  }

  function clear() {
    strokesRef.current = [];
    redraw();
    publish();
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div
        className="relative overflow-hidden rounded-2xl"
        style={{ background: "var(--panel-raised)", border: `1.5px dashed ${empty ? "var(--border-strong, var(--border))" : "var(--primary)"}` }}
      >
        <canvas
          ref={canvasRef}
          width={PAD_WIDTH}
          height={PAD_HEIGHT}
          role="img"
          aria-label={t("signPadLabel")}
          data-testid="signature-pad"
          className="block h-36 w-full touch-none"
          style={{ color: "var(--text)", cursor: disabled ? "default" : "crosshair" }}
          onPointerDown={start}
          onPointerMove={move}
          onPointerUp={end}
          onPointerLeave={end}
          onPointerCancel={end}
        />
        {empty ? (
          <span className="pointer-events-none absolute inset-0 grid place-items-center text-sm font-semibold" style={{ color: "var(--dim)" }}>
            {t("signPadHint")}
          </span>
        ) : null}
      </div>
      {!empty ? (
        <button type="button" onClick={clear} className="self-end text-xs font-semibold underline-offset-4 hover:underline" style={{ color: "var(--text-soft)" }}>
          {t("signPadClear")}
        </button>
      ) : null}
    </div>
  );
}
