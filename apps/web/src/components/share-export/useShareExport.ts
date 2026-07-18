"use client";

import { useMemo } from "react";

import type { ShareExportCopy } from "@/components/share-export/ShareExportDialog";
import { useUiTranslations } from "@/i18n/ui";
import type { ExportLabels } from "@/lib/document-export";

export function useShareExport() {
  const i18n = useUiTranslations();

  return useMemo((): { copy: ShareExportCopy; labels: ExportLabels } => ({
    copy: {
      title: i18n("shareExportTitle"),
      chooseFormat: i18n("shareExportChooseFormat"),
      chooseDestination: i18n("shareExportChooseDestination"),
      formatHelp: i18n("shareExportFormatHelp"),
      download: i18n("shareExportDownload"),
      share: i18n("shareExportShareFile"),
      export: i18n("shareExportExport"),
      email: i18n("shareExportEmail"),
      googleDrive: i18n("shareExportGoogleDrive"),
      oneDrive: i18n("shareExportOneDrive"),
      iCloudDrive: i18n("shareExportICloudDrive"),
      social: i18n("shareExportSocialApps"),
      otherApps: i18n("shareExportOtherApps"),
      close: i18n("closebbfa773"),
      working: i18n("shareExportPreparing"),
      ready: i18n("shareExportReady"),
      downloadedFallback: i18n("shareExportDownloadedFallback"),
      shareUnavailable: i18n("shareExportUnavailable"),
      copiedFallback: i18n("shareExportCopiedFallback"),
      failed: i18n("shareExportFailed"),
      formatPdf: i18n("shareExportFormatPdf"),
      formatMarkdown: i18n("shareExportFormatMarkdown"),
      formatText: i18n("shareExportFormatText"),
      formatOdt: i18n("shareExportFormatOdt"),
      formatCsv: i18n("shareExportFormatCsv"),
    },
    labels: {
      appName: "Milos Training",
      workout: i18n("exportWorkout"),
      workoutHistory: i18n("exportWorkoutHistory"),
      personalRecord: i18n("exportPersonalRecord"),
      personalRecords: i18n("personalRecords4769a96"),
      type: i18n("exportType"),
      status: i18n("exportStatus"),
      scale: i18n("exportScale"),
      scales: i18n("exportScales"),
      date: i18n("exportDate"),
      source: i18n("exportSource"),
      duration: i18n("exportDuration"),
      sections: i18n("exportSections"),
      exercises: i18n("exportExercises"),
      scores: i18n("exportScores"),
      notes: i18n("exportNotes"),
      modifications: i18n("exportModifications"),
      supportingDetails: i18n("exportSupportingDetails"),
      comparison: i18n("exportComparison"),
      higherIsBetter: i18n("exportHigherIsBetter"),
      lowerIsBetter: i18n("exportLowerIsBetter"),
      prescribed: i18n("exportPrescribed"),
      actual: i18n("exportActual"),
      baseOnly: i18n("exportBaseOnly"),
      none: i18n("exportNone"),
      generatedBy: i18n("exportGeneratedBy"),
      teamWorkout: i18n("exportTeamWorkout"),
      setsLabel: i18n("exportSets"),
      roundsLabel: i18n("exportRounds"),
      excluded: i18n("exportExcluded"),
      basePrescription: i18n("exportBasePrescription"),
      load: i18n("exportLoad"),
      yes: i18n("exportYes"),
      no: i18n("exportNo"),
      session: i18n("exportSession"),
      score: i18n("exportScore"),
    },
  }), [i18n]);
}
