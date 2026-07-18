import type { WorkoutExecution } from "@/api/executions";
import type { PRRecord } from "@/api/gamification";
import type {
  WorkoutExerciseRecord,
  WorkoutRecord,
  WorkoutVariationRecord,
} from "@/api/workouts";

export type ExportFormat = "pdf" | "md" | "txt" | "odt" | "csv";

export type ExportLabels = {
  appName: string;
  workout: string;
  workoutHistory: string;
  personalRecord: string;
  type: string;
  status: string;
  scale: string;
  scales: string;
  date: string;
  source: string;
  duration: string;
  sections: string;
  exercises: string;
  scores: string;
  notes: string;
  modifications: string;
  supportingDetails: string;
  comparison: string;
  higherIsBetter: string;
  lowerIsBetter: string;
  prescribed: string;
  actual: string;
  baseOnly: string;
  none: string;
  generatedBy: string;
};

export type ExportItem = {
  label?: string;
  value: string;
  details?: string[];
};

export type ExportSection = {
  icon: string;
  title: string;
  items: ExportItem[];
};

export type ExportDocument = {
  icon: string;
  category: string;
  title: string;
  subtitle?: string;
  metadata: Array<{ label: string; value: string }>;
  sections: ExportSection[];
  footer: string;
};

const MIME_TYPES: Record<ExportFormat, string> = {
  pdf: "application/pdf",
  md: "text/markdown;charset=utf-8",
  txt: "text/plain;charset=utf-8",
  odt: "application/vnd.oasis.opendocument.text",
  csv: "text/csv;charset=utf-8",
};

function compact(values: Array<string | null | undefined>): string[] {
  return values.filter((value): value is string => Boolean(value));
}

function displayValue(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  return String(value).replaceAll("_", " ");
}

function duration(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.round(milliseconds / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    : `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function prescription(exercise: WorkoutExerciseRecord | WorkoutVariationRecord): string {
  const parts: string[] = [];
  const sets = exercise.sets;
  const value = exercise.prescription_value;
  const unit = exercise.prescription_unit;

  if (sets && value !== null && value !== undefined) {
    parts.push(`${sets} × ${displayValue(value)}${unit ? ` ${displayValue(unit)}` : ""}`);
  } else if (value !== null && value !== undefined) {
    parts.push(`${displayValue(value)}${unit ? ` ${displayValue(unit)}` : ""}`);
  } else if (sets) {
    parts.push(`${sets} sets`);
  }

  if (exercise.load_value !== null && exercise.load_value !== undefined) {
    parts.push(`${displayValue(exercise.load_value)} ${displayValue(exercise.load_mode ?? "load")}`);
  }

  return parts.join(" · ") || "—";
}

function variationDetail(variation: WorkoutVariationRecord, base: WorkoutExerciseRecord): string {
  const name = variation.scale_level.label;
  if (variation.excluded) return `${name}: excluded`;
  const merged = {
    ...variation,
    sets: variation.sets ?? base.sets,
    prescription_unit: variation.prescription_unit ?? base.prescription_unit,
    load_mode: variation.load_mode ?? base.load_mode,
  };
  const override = compact([
    variation.exercise_name_override ?? undefined,
    prescription(merged),
    variation.description ?? undefined,
  ]).filter((value, index, values) => value !== "—" && values.indexOf(value) === index);
  return `${name}: ${override.join(" · ") || "base prescription"}`;
}

function timerSummary(timer: Record<string, unknown> | null | undefined): string | undefined {
  if (!timer) return undefined;
  const type = displayValue(timer.type);
  const durationSeconds = Number(timer.duration_seconds ?? 0);
  const rounds = Number(timer.rounds ?? 0);
  return compact([
    type,
    durationSeconds > 0 ? duration(durationSeconds * 1000) : undefined,
    rounds > 0 ? `${rounds} rounds` : undefined,
  ]).join(" · ");
}

export function buildWorkoutDocument(workout: WorkoutRecord, labels: ExportLabels): ExportDocument {
  return {
    icon: "🏋️",
    category: labels.workout,
    title: workout.title || labels.workout,
    subtitle: workout.is_team_workout ? "Team workout" : undefined,
    metadata: [
      { label: labels.type, value: displayValue(workout.type) },
      { label: labels.status, value: displayValue(workout.status ?? "published") },
      {
        label: labels.scales,
        value: workout.available_scale_levels.length > 0
          ? workout.available_scale_levels.map((scale) => scale.label).join(", ")
          : labels.baseOnly,
      },
      { label: labels.sections, value: String(workout.sections.length) },
    ],
    sections: workout.sections
      .slice()
      .sort((a, b) => a.order - b.order)
      .map((section) => ({
        icon: section.scoreable ? "🎯" : "⚡",
        title: section.name,
        items: section.exercises
          .slice()
          .sort((a, b) => a.order - b.order)
          .map((exercise) => ({
            label: exercise.name,
            value: prescription(exercise),
            details: compact([
              exercise.description ?? undefined,
              timerSummary(section.timer_config),
              ...exercise.variations.map((variation) => variationDetail(variation, exercise)),
            ]),
          })),
      })),
    footer: labels.generatedBy,
  };
}

export function buildExecutionDocument(
  execution: WorkoutExecution,
  labels: ExportLabels,
  locale: string,
): ExportDocument {
  const completedDate = execution.completed_at_utc ?? execution.started_at_utc;
  const sections: ExportSection[] = [];

  if (execution.section_scores.length > 0) {
    sections.push({
      icon: "🏁",
      title: labels.scores,
      items: execution.section_scores.map((score) => ({
        label: score.section_name ?? score.score_type ?? labels.scores,
        value: `${displayValue(score.value)}${score.unit ? ` ${displayValue(score.unit)}` : ""}`,
      })),
    });
  }

  if (execution.exercise_modifications.length > 0) {
    sections.push({
      icon: "🔧",
      title: labels.modifications,
      items: execution.exercise_modifications.map((change) => ({
        label: change.exercise_name ?? change.section_name ?? displayValue(change.field),
        value: `${labels.prescribed}: ${displayValue(change.canonical_value)} → ${labels.actual}: ${displayValue(change.actual_value)}${change.unit ? ` ${displayValue(change.unit)}` : ""}`,
        details: compact([change.note ?? undefined]),
      })),
    });
  }

  if (execution.exercise_notes.length > 0) {
    sections.push({
      icon: "📝",
      title: labels.notes,
      items: execution.exercise_notes.map((note) => ({
        label: note.selected_text || labels.notes,
        value: note.note_text || note.tags?.join(", ") || "—",
        details: note.tags?.length ? [note.tags.join(" · ")] : undefined,
      })),
    });
  }

  return {
    icon: "✅",
    category: labels.workoutHistory,
    title: execution.workout_title ?? labels.workout,
    metadata: [
      { label: labels.date, value: new Date(completedDate).toLocaleString(locale) },
      { label: labels.type, value: displayValue(execution.workout_type ?? "session") },
      { label: labels.scale, value: displayValue(execution.scale_level_slug ?? labels.baseOnly) },
      { label: labels.source, value: displayValue(execution.source) },
      { label: labels.duration, value: duration(execution.total_elapsed_ms) },
      { label: labels.status, value: displayValue(execution.status) },
    ],
    sections,
    footer: labels.generatedBy,
  };
}

export function buildPRDocument(pr: PRRecord, labels: ExportLabels, locale: string): ExportDocument {
  const details = Object.entries(pr.supporting_metrics ?? {}).map(([key, value]) => ({
    label: displayValue(key).replace(/^./, (character) => character.toLocaleUpperCase(locale)),
    value: displayValue(value),
  }));
  const sections: ExportSection[] = [];

  if (details.length > 0) {
    sections.push({ icon: "📊", title: labels.supportingDetails, items: details });
  }
  if (pr.notes) {
    sections.push({ icon: "📝", title: labels.notes, items: [{ value: pr.notes }] });
  }

  return {
    icon: "🏆",
    category: labels.personalRecord,
    title: pr.name,
    subtitle: `${displayValue(pr.current_score)} ${displayValue(pr.unit)}`,
    metadata: [
      { label: "Score", value: `${displayValue(pr.current_score)} ${displayValue(pr.unit)}` },
      { label: labels.date, value: new Date(`${pr.beaten_on}T00:00:00`).toLocaleDateString(locale) },
      { label: labels.comparison, value: pr.higher_is_better ? labels.higherIsBetter : labels.lowerIsBetter },
    ],
    sections,
    footer: labels.generatedBy,
  };
}

function markdownEscape(value: string): string {
  return value.replaceAll("|", "\\|").replaceAll("\n", " ");
}

export function renderMarkdown(document: ExportDocument): string {
  const lines = [
    `# ${document.icon} ${document.title}`,
    "",
    `_${document.category}_`,
    ...(document.subtitle ? ["", `**${document.subtitle}**`] : []),
    "",
    ...document.metadata.flatMap(({ label, value }) => [`- **${label}:** ${value}`]),
  ];

  for (const section of document.sections) {
    lines.push("", `## ${section.icon} ${section.title}`, "");
    for (const item of section.items) {
      lines.push(`- ${item.label ? `**${item.label}:** ` : ""}${item.value}`);
      for (const detail of item.details ?? []) lines.push(`  - ${detail}`);
    }
  }

  lines.push("", "---", document.footer, "");
  return lines.join("\n");
}

export function renderText(document: ExportDocument): string {
  const lines = [
    `${document.icon} ${document.title}`,
    document.category.toUpperCase(),
    ...(document.subtitle ? [document.subtitle] : []),
    "",
    ...document.metadata.map(({ label, value }) => `${label}: ${value}`),
  ];

  for (const section of document.sections) {
    lines.push("", `${section.icon} ${section.title}`);
    for (const item of section.items) {
      lines.push(`• ${item.label ? `${item.label}: ` : ""}${item.value}`);
      for (const detail of item.details ?? []) lines.push(`  ↳ ${detail}`);
    }
  }

  lines.push("", document.footer, "");
  return lines.join("\n");
}

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export function renderCsv(document: ExportDocument): string {
  const rows: string[][] = [
    ["Section", "Label", "Value"],
    [document.category, "Title", document.title],
    ...(document.subtitle ? [[document.category, "Subtitle", document.subtitle]] : []),
    ...document.metadata.map(({ label, value }) => ["Metadata", label, value]),
  ];

  for (const section of document.sections) {
    for (const item of section.items) {
      rows.push([section.title, item.label ?? "", item.value]);
      for (const detail of item.details ?? []) rows.push([section.title, item.label ?? "Detail", detail]);
    }
  }

  return `\uFEFF${rows.map((row) => row.map((cell) => csvCell(markdownEscape(cell))).join(",")).join("\r\n")}\r\n`;
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

async function renderOdt(document: ExportDocument): Promise<Blob> {
  const { default: JSZip } = await import("jszip");
  const zip = new JSZip();
  zip.file("mimetype", MIME_TYPES.odt, { compression: "STORE" });

  const paragraphs = [
    `<text:p text:style-name="Category">${xmlEscape(`${document.icon} ${document.category}`)}</text:p>`,
    `<text:h text:style-name="Title" text:outline-level="1">${xmlEscape(document.title)}</text:h>`,
    ...(document.subtitle ? [`<text:p text:style-name="Subtitle">${xmlEscape(document.subtitle)}</text:p>`] : []),
    ...document.metadata.map(({ label, value }) =>
      `<text:p text:style-name="Meta"><text:span text:style-name="MetaLabel">${xmlEscape(label)}:</text:span> ${xmlEscape(value)}</text:p>`),
    ...document.sections.flatMap((section) => [
      `<text:h text:style-name="Section" text:outline-level="2">${xmlEscape(`${section.icon} ${section.title}`)}</text:h>`,
      ...section.items.flatMap((item) => [
        `<text:p text:style-name="Item">${item.label ? `<text:span text:style-name="ItemLabel">${xmlEscape(item.label)}:</text:span> ` : ""}${xmlEscape(item.value)}</text:p>`,
        ...(item.details ?? []).map((detail) => `<text:p text:style-name="Detail">↳ ${xmlEscape(detail)}</text:p>`),
      ]),
    ]),
    `<text:p text:style-name="Footer">${xmlEscape(document.footer)}</text:p>`,
  ].join("");

  zip.file("content.xml", `<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" office:version="1.3">
<office:automatic-styles>
  <style:style style:name="Category" style:family="paragraph"><style:paragraph-properties fo:margin-bottom="0.08in"/><style:text-properties fo:color="#7C3AED" fo:font-weight="bold" fo:font-size="11pt"/></style:style>
  <style:style style:name="Title" style:family="paragraph"><style:paragraph-properties fo:margin-bottom="0.12in"/><style:text-properties fo:color="#172033" fo:font-weight="bold" fo:font-size="25pt"/></style:style>
  <style:style style:name="Subtitle" style:family="paragraph"><style:text-properties fo:color="#DB2777" fo:font-weight="bold" fo:font-size="15pt"/></style:style>
  <style:style style:name="Meta" style:family="paragraph"><style:paragraph-properties fo:margin-bottom="0.04in"/><style:text-properties fo:color="#475569"/></style:style>
  <style:style style:name="MetaLabel" style:family="text"><style:text-properties fo:color="#7C3AED" fo:font-weight="bold"/></style:style>
  <style:style style:name="Section" style:family="paragraph"><style:paragraph-properties fo:margin-top="0.2in" fo:margin-bottom="0.08in"/><style:text-properties fo:color="#0F766E" fo:font-weight="bold" fo:font-size="16pt"/></style:style>
  <style:style style:name="Item" style:family="paragraph"><style:paragraph-properties fo:margin-left="0.12in" fo:margin-bottom="0.05in"/><style:text-properties fo:color="#172033"/></style:style>
  <style:style style:name="ItemLabel" style:family="text"><style:text-properties fo:font-weight="bold" fo:color="#DB2777"/></style:style>
  <style:style style:name="Detail" style:family="paragraph"><style:paragraph-properties fo:margin-left="0.3in"/><style:text-properties fo:color="#64748B" fo:font-size="9pt"/></style:style>
  <style:style style:name="Footer" style:family="paragraph"><style:paragraph-properties fo:margin-top="0.3in"/><style:text-properties fo:color="#94A3B8" fo:font-size="8pt"/></style:style>
</office:automatic-styles><office:body><office:text>${paragraphs}</office:text></office:body></office:document-content>`);
  zip.file("styles.xml", `<?xml version="1.0" encoding="UTF-8"?><office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" office:version="1.3"><office:styles/></office:document-styles>`);
  zip.file("meta.xml", `<?xml version="1.0" encoding="UTF-8"?><office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" office:version="1.3"><office:meta/></office:document-meta>`);
  zip.file("META-INF/manifest.xml", `<?xml version="1.0" encoding="UTF-8"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3"><manifest:file-entry manifest:full-path="/" manifest:media-type="${MIME_TYPES.odt}"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/></manifest:manifest>`);
  return zip.generateAsync({ type: "blob", mimeType: MIME_TYPES.odt, compression: "DEFLATE" });
}

async function renderPdf(document: ExportDocument): Promise<Blob> {
  const { jsPDF } = await import("jspdf");
  const pdf = new jsPDF({ unit: "pt", format: "a4" });
  const pageWidth = pdf.internal.pageSize.getWidth();
  const pageHeight = pdf.internal.pageSize.getHeight();
  const margin = 48;
  const contentWidth = pageWidth - margin * 2;
  let y = 44;

  const ensureSpace = (height: number) => {
    if (y + height <= pageHeight - 44) return;
    pdf.addPage();
    y = 48;
  };
  const textBlock = (text: string, size: number, color: [number, number, number], options?: { bold?: boolean; indent?: number }) => {
    const indent = options?.indent ?? 0;
    pdf.setFont("helvetica", options?.bold ? "bold" : "normal");
    pdf.setFontSize(size);
    pdf.setTextColor(...color);
    const lines = pdf.splitTextToSize(text, contentWidth - indent);
    const height = lines.length * (size * 1.35);
    ensureSpace(height + 5);
    pdf.text(lines, margin + indent, y);
    y += height + 5;
  };

  pdf.setFillColor(124, 58, 237);
  pdf.roundedRect(margin, y, contentWidth, 24, 8, 8, "F");
  pdf.setTextColor(255, 255, 255);
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(10);
  pdf.text(document.category.toUpperCase(), margin + 12, y + 16);
  y += 44;
  textBlock(document.title, 27, [23, 32, 51], { bold: true });
  if (document.subtitle) textBlock(document.subtitle, 15, [219, 39, 119], { bold: true });
  y += 5;

  for (const meta of document.metadata) {
    ensureSpace(22);
    pdf.setFillColor(246, 243, 255);
    pdf.roundedRect(margin, y - 11, contentWidth, 20, 5, 5, "F");
    pdf.setFont("helvetica", "bold");
    pdf.setFontSize(9);
    pdf.setTextColor(124, 58, 237);
    pdf.text(`${meta.label}:`, margin + 9, y + 2);
    pdf.setFont("helvetica", "normal");
    pdf.setTextColor(71, 85, 105);
    pdf.text(pdf.splitTextToSize(meta.value, contentWidth * 0.68)[0] ?? "", margin + 120, y + 2);
    y += 25;
  }

  for (const section of document.sections) {
    y += 10;
    ensureSpace(42);
    pdf.setDrawColor(13, 148, 136);
    pdf.setLineWidth(3);
    pdf.line(margin, y - 12, margin, y + 8);
    textBlock(section.title, 16, [15, 118, 110], { bold: true, indent: 12 });
    for (const item of section.items) {
      textBlock(item.label ? `${item.label}: ${item.value}` : item.value, 11, [23, 32, 51], { bold: Boolean(item.label), indent: 12 });
      for (const detail of item.details ?? []) textBlock(`• ${detail}`, 9, [100, 116, 139], { indent: 26 });
    }
  }

  y += 14;
  textBlock(document.footer, 8, [148, 163, 184]);
  return pdf.output("blob");
}

export function exportFilename(document: ExportDocument, format: ExportFormat): string {
  const slug = document.title
    .normalize("NFKD")
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-|-$/g, "")
    .toLocaleLowerCase()
    .slice(0, 72) || "milos-training";
  return `${slug}.${format}`;
}

export async function generateExportFile(document: ExportDocument, format: ExportFormat): Promise<File> {
  let blob: Blob;
  if (format === "pdf") blob = await renderPdf(document);
  else if (format === "odt") blob = await renderOdt(document);
  else {
    const content = format === "md" ? renderMarkdown(document) : format === "csv" ? renderCsv(document) : renderText(document);
    blob = new Blob([content], { type: MIME_TYPES[format] });
  }
  return new File([blob], exportFilename(document, format), { type: MIME_TYPES[format] });
}
