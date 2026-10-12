import type { OrganizationPurgeStatus, RetentionDisposition } from "@/api/platform-organizations";

const en = {
  open: "Export & purge",
  title: "Reviewed export and purge",
  intro:
    "Purging permanently removes this organization after a full export and a retention review. Requesting a purge suspends the organization immediately.",
  noPurge: "No purge has been requested for this organization.",
  request: "Request export & purge",
  requesting: "Requesting...",
  refresh: "Refresh status",
  close: "Close",
  status: "Status",
  requestedAt: "Requested",
  exportReady: "Full export",
  download: "Download export (ZIP)",
  downloadExpires: "The download link expires after 15 minutes; refresh to get a new one.",
  exportSize: "Size",
  bytes: "{size} bytes",
  exportChecksum: "SHA-256",
  retentionTitle: "Retention review",
  retentionContext: "Context",
  retentionPolicy: "Policy",
  retentionRecords: "Records",
  retentionUntil: "Kept until",
  approveTitle: "Approve purge",
  approveBody:
    "Download and verify the export first. Retained records stay in the retention archive; everything else is deleted. Type the organization slug to confirm.",
  confirmationLabel: "Type {slug} to confirm",
  approve: "Approve and purge",
  approving: "Approving...",
  cancelPurge: "Cancel purge",
  cancelling: "Cancelling...",
  resume: "Retry",
  resuming: "Retrying...",
  failedBody: "The {stage} stage failed: {reason}.",
  stageExport: "export",
  stagePurge: "purge",
  workingBody: "Background processing is running. Refresh to see progress.",
  completedBody: "The organization was purged. The audit record and retention archive remain.",
  cancelledBody: "This purge was cancelled. The organization stays suspended until it is reactivated.",
  approvedBy: "Approval",
  approvalSecondVendor: "Second vendor",
  approvalTyped: "Typed confirmation",
  actionError: "The purge action could not be completed.",
  loadError: "The purge status could not be loaded.",
};

export type PlatformOrganizationPurgeCopy = { [Key in keyof typeof en]: string } & {
  statuses: Record<OrganizationPurgeStatus, string>;
  dispositions: Record<RetentionDisposition, string>;
};

const enStatuses: Record<OrganizationPurgeStatus, string> = {
  requested: "Requested",
  exporting: "Exporting",
  exported: "Awaiting approval",
  approved: "Approved",
  purging: "Purging",
  completed: "Completed",
  failed: "Failed",
  cancelled: "Cancelled",
};

const enDispositions: Record<RetentionDisposition, string> = {
  purge: "Purge",
  retain: "Retain",
  retain_anonymized: "Retain anonymized",
};

const el: PlatformOrganizationPurgeCopy = {
  open: "Εξαγωγή & οριστική εκκαθάριση",
  title: "Ελεγχόμενη εξαγωγή και εκκαθάριση",
  intro:
    "Η εκκαθάριση αφαιρεί οριστικά τον οργανισμό μετά από πλήρη εξαγωγή και έλεγχο διατήρησης. Το αίτημα εκκαθάρισης θέτει αμέσως τον οργανισμό σε αναστολή.",
  noPurge: "Δεν έχει ζητηθεί εκκαθάριση για αυτόν τον οργανισμό.",
  request: "Αίτημα εξαγωγής & εκκαθάρισης",
  requesting: "Υποβολή...",
  refresh: "Ανανέωση κατάστασης",
  close: "Κλείσιμο",
  status: "Κατάσταση",
  requestedAt: "Ζητήθηκε",
  exportReady: "Πλήρης εξαγωγή",
  download: "Λήψη εξαγωγής (ZIP)",
  downloadExpires: "Ο σύνδεσμος λήψης λήγει σε 15 λεπτά· κάνε ανανέωση για νέο.",
  exportSize: "Μέγεθος",
  bytes: "{size} bytes",
  exportChecksum: "SHA-256",
  retentionTitle: "Έλεγχος διατήρησης",
  retentionContext: "Ενότητα",
  retentionPolicy: "Πολιτική",
  retentionRecords: "Εγγραφές",
  retentionUntil: "Διατήρηση έως",
  approveTitle: "Έγκριση εκκαθάρισης",
  approveBody:
    "Κατέβασε και έλεγξε πρώτα την εξαγωγή. Οι εγγραφές προς διατήρηση μένουν στο αρχείο διατήρησης· όλα τα υπόλοιπα διαγράφονται. Πληκτρολόγησε το slug του οργανισμού για επιβεβαίωση.",
  confirmationLabel: "Πληκτρολόγησε {slug} για επιβεβαίωση",
  approve: "Έγκριση και εκκαθάριση",
  approving: "Έγκριση...",
  cancelPurge: "Ακύρωση εκκαθάρισης",
  cancelling: "Ακύρωση...",
  resume: "Νέα προσπάθεια",
  resuming: "Νέα προσπάθεια...",
  failedBody: "Το στάδιο {stage} απέτυχε: {reason}.",
  stageExport: "εξαγωγής",
  stagePurge: "εκκαθάρισης",
  workingBody: "Η επεξεργασία στο παρασκήνιο εκτελείται. Κάνε ανανέωση για να δεις την πρόοδο.",
  completedBody: "Ο οργανισμός εκκαθαρίστηκε. Η εγγραφή ελέγχου και το αρχείο διατήρησης παραμένουν.",
  cancelledBody: "Η εκκαθάριση ακυρώθηκε. Ο οργανισμός παραμένει σε αναστολή μέχρι να ενεργοποιηθεί ξανά.",
  approvedBy: "Έγκριση",
  approvalSecondVendor: "Δεύτερος vendor",
  approvalTyped: "Πληκτρολογημένη επιβεβαίωση",
  actionError: "Δεν ήταν δυνατή η ολοκλήρωση της ενέργειας εκκαθάρισης.",
  loadError: "Δεν ήταν δυνατή η φόρτωση της κατάστασης εκκαθάρισης.",
  statuses: {
    requested: "Ζητήθηκε",
    exporting: "Εξαγωγή",
    exported: "Αναμονή έγκρισης",
    approved: "Εγκρίθηκε",
    purging: "Εκκαθάριση",
    completed: "Ολοκληρώθηκε",
    failed: "Απέτυχε",
    cancelled: "Ακυρώθηκε",
  },
  dispositions: {
    purge: "Διαγραφή",
    retain: "Διατήρηση",
    retain_anonymized: "Ανώνυμη διατήρηση",
  },
};

const enCopy: PlatformOrganizationPurgeCopy = { ...en, statuses: enStatuses, dispositions: enDispositions };

export function platformOrganizationPurgeCopy(locale: string): PlatformOrganizationPurgeCopy {
  return locale === "el" ? el : enCopy;
}

export function formatPurgeCopy(template: string, values: Record<string, string>) {
  return template.replace(/\{(\w+)\}/g, (match, key: string) => values[key] ?? match);
}
