export type IcsEvent = {
  title: string;
  date: string;
  datetime?: string;
  durationMinutes?: number;
  description?: string;
  location?: string;
};

function toUtcCompact(iso: string): string {
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, "0");
  return (
    `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
    `T${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`
  );
}

function toDateCompact(yyyyMmDd: string): string {
  return yyyyMmDd.replace(/-/g, "");
}

export function downloadIcsEvent(event: IcsEvent): void {
  const uid = `milos-${Date.now()}@milos-training`;
  const dtstamp = toUtcCompact(new Date().toISOString());

  const dtstart = event.datetime
    ? `DTSTART:${toUtcCompact(event.datetime)}`
    : `DTSTART;VALUE=DATE:${toDateCompact(event.date)}`;

  const dtend = event.datetime
    ? `DTEND:${toUtcCompact(new Date(new Date(event.datetime).getTime() + (event.durationMinutes ?? 60) * 60_000).toISOString())}`
    : `DTEND;VALUE=DATE:${toDateCompact(event.date)}`;

  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Milos Training//EN",
    "BEGIN:VEVENT",
    `UID:${uid}`,
    `DTSTAMP:${dtstamp}`,
    dtstart,
    dtend,
    `SUMMARY:${event.title}`,
    event.description ? `DESCRIPTION:${event.description.replace(/[\r\n]+/g, "\\n")}` : "",
    event.location ? `LOCATION:${event.location}` : "",
    "END:VEVENT",
    "END:VCALENDAR",
  ]
    .filter(Boolean)
    .join("\r\n");

  const blob = new Blob([lines], { type: "text/calendar;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `${event.title.replace(/[^\w\s-]/g, "").replace(/\s+/g, "-").toLowerCase()}.ics`;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}
