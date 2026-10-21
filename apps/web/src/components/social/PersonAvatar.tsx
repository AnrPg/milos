import { clubInitials } from "@/components/community/community";

/** A person's photo, or their initials on a neutral disc. */
export function PersonAvatar({ name, url, size = 40 }: { name?: string | null; url?: string | null; size?: number }) {
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
    return <img src={url} alt="" className="shrink-0 rounded-full object-cover" style={{ width: size, height: size }} />;
  }
  return (
    <span
      aria-hidden="true"
      className="flex shrink-0 items-center justify-center rounded-full font-extrabold"
      style={{ width: size, height: size, fontSize: size * 0.36, background: "var(--panel-raised)", color: "var(--text)" }}
    >
      {clubInitials(name ?? "?")}
    </span>
  );
}
