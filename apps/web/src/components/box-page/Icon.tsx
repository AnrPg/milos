import { AMENITY_ICONS, UI_ICONS, type UiIcon } from "./icons";

/** A Lucide line icon from the copied-in markup (static strings, never user input). */
export function Icon({ name, amenity, size = 20 }: { name?: UiIcon; amenity?: string; size?: number }) {
  const markup = name ? UI_ICONS[name] : amenity ? AMENITY_ICONS[amenity] : undefined;
  if (!markup) return null;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className="shrink-0"
      dangerouslySetInnerHTML={{ __html: markup }}
    />
  );
}
