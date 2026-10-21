"use client";

import Image from "next/image";
import { useTranslations } from "next-intl";

import type { EntrySource } from "@/api/providers";
import { clubInitials } from "@/components/community/community";
import { useSourceDirectory } from "@/components/providers/use-providers";
import { showsSource, sourceColor, type SourceDirectory } from "@/lib/provider-sources";

/** «Box Κυψέλη», «Νίκος Π. (πρώην)», «Ελεύθερη», «Garmin». */
export function useSourceName() {
  const t = useTranslations("Providers");
  return (source: EntrySource) => {
    if (source.kind === "freeform") return t("source.freeform");
    if (source.kind === "device") return source.name?.trim() || t("source.device");
    const name = source.name?.trim() || t("source.unknown");
    return source.former ? t("source.former", { name }) : name;
  };
}

/**
 * The small source label on an entry (board 17 Q3): shown for freeform and
 * device entries and providers you left, and for providers' entries once
 * there is more than one provider to tell apart.
 */
export function SourceLabel({
  source,
  directory,
  always,
}: {
  source: EntrySource | null | undefined;
  /** Pass when rendering many labels, to read the providers once. */
  directory?: SourceDirectory;
  /** Show even with a single provider (the merged «Σήμερα»). */
  always?: boolean;
}) {
  const fallback = useSourceDirectory();
  const name = useSourceName();
  const dir = directory ?? fallback;
  if (!source || (!always && !showsSource(source, dir))) return null;
  const color = sourceColor(source, dir);
  return (
    <span
      className="inline-flex max-w-full items-center truncate rounded-full px-2 py-0.5 text-[11px] font-semibold"
      style={{ background: `color-mix(in srgb, ${color} 16%, transparent)`, color }}
      data-source={source.kind}
    >
      {name(source)}
    </span>
  );
}

export function ProviderAvatar({
  name,
  logoUrl,
  color,
  size = 40,
}: {
  name: string;
  logoUrl?: string | null;
  color: string;
  size?: number;
}) {
  if (logoUrl?.trim()) {
    return (
      <Image
        alt=""
        aria-hidden="true"
        src={logoUrl}
        width={size}
        height={size}
        unoptimized
        className="shrink-0 rounded-full object-cover"
        style={{ width: size, height: size }}
      />
    );
  }
  return (
    <span
      aria-hidden="true"
      className="flex shrink-0 items-center justify-center rounded-full text-sm font-extrabold"
      style={{ width: size, height: size, background: color, color: "var(--on-series)" }}
    >
      {clubInitials(name)}
    </span>
  );
}
