import type { OrganizationPurgeStatus, RetentionDisposition } from "@/api/platform-organizations";

const en = {
  open: "Delete permanently…",
  title: "Delete organization permanently",
  intro:
    "Deleting removes the organization, all of its data and the accounts that belong only to it. It always takes four steps, so nothing is lost by accident:",
  step1: "Export. Palee collects all of the organization's data into one ZIP file. This suspends the organization; you can cancel until step 4.",
  step2: "Back up. Download the ZIP and keep it somewhere safe. It is the only copy of what will be deleted.",
  step3: "Confirm. Tick that you saved the backup and type the organization's slug.",
  step4: "Delete. Every area is deleted in order. Accounting records move to a sealed archive for the legal retention period, anonymised usage counts stay for two years, and accounts that also belong to another organization are kept.",
  noPurge: "Nothing has started yet.",
  request: "Step 1: export the data",
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
  retentionDeleted: "Deleted",
  approveTitle: "Confirm permanent deletion",
  approveBody: "This cannot be undone. Retained records stay in the retention archive; everything else is deleted.",
  backupSaved: "I downloaded the export and saved it somewhere safe.",
  confirmationLabel: "Type {slug} to confirm",
  approve: "Delete permanently",
  approving: "Approving...",
  cancelPurge: "Cancel and keep the organization",
  cancelling: "Cancelling...",
  resume: "Retry",
  resuming: "Retrying...",
  failedBody: "The {stage} stage failed: {reason}.",
  stageExport: "export",
  stagePurge: "purge",
  failedHint: "Retry continues where it stopped; finished areas are not run again. The export stays downloadable until the deletion finishes.",
  keptAccounts: "{count} account(s) kept because another organization's records still use them. Held by:",
  workingBody: "Background processing is running. Refresh to see progress.",
  completedBody: "The organization was deleted. The audit record and retention archive remain.",
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
  open: "Οριστική διαγραφή…",
  title: "Οριστική διαγραφή οργανισμού",
  intro:
    "Η διαγραφή αφαιρεί τον οργανισμό, όλα τα δεδομένα του και τους λογαριασμούς που ανήκουν μόνο σε αυτόν. Γίνεται πάντα σε τέσσερα βήματα, ώστε να μη χαθεί τίποτα κατά λάθος:",
  step1: "Εξαγωγή. Το Palee συγκεντρώνει όλα τα δεδομένα του οργανισμού σε ένα αρχείο ZIP. Ο οργανισμός τίθεται σε αναστολή· μπορείς να ακυρώσεις μέχρι το βήμα 4.",
  step2: "Αντίγραφο. Κατέβασε το ZIP και φύλαξέ το σε ασφαλές μέρος. Είναι το μόνο αντίγραφο όσων θα διαγραφούν.",
  step3: "Επιβεβαίωση. Σημείωσε ότι αποθήκευσες το αντίγραφο και πληκτρολόγησε το slug του οργανισμού.",
  step4: "Διαγραφή. Κάθε ενότητα διαγράφεται με σειρά. Οι λογιστικές εγγραφές μεταφέρονται σε σφραγισμένο αρχείο για τη νόμιμη περίοδο διατήρησης, τα ανώνυμα στατιστικά χρήσης μένουν δύο χρόνια και οι λογαριασμοί που ανήκουν και σε άλλον οργανισμό διατηρούνται.",
  noPurge: "Δεν έχει ξεκινήσει τίποτα ακόμη.",
  request: "Βήμα 1: εξαγωγή δεδομένων",
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
  retentionDeleted: "Διαγράφηκαν",
  approveTitle: "Επιβεβαίωση οριστικής διαγραφής",
  approveBody: "Δεν αναιρείται. Οι εγγραφές προς διατήρηση μένουν στο αρχείο διατήρησης· όλα τα υπόλοιπα διαγράφονται.",
  backupSaved: "Κατέβασα την εξαγωγή και την αποθήκευσα σε ασφαλές μέρος.",
  confirmationLabel: "Πληκτρολόγησε {slug} για επιβεβαίωση",
  approve: "Οριστική διαγραφή",
  approving: "Έγκριση...",
  cancelPurge: "Ακύρωση και διατήρηση του οργανισμού",
  cancelling: "Ακύρωση...",
  resume: "Νέα προσπάθεια",
  resuming: "Νέα προσπάθεια...",
  failedBody: "Το στάδιο {stage} απέτυχε: {reason}.",
  stageExport: "εξαγωγής",
  stagePurge: "εκκαθάρισης",
  failedHint: "Η νέα προσπάθεια συνεχίζει από εκεί που σταμάτησε· οι ενότητες που ολοκληρώθηκαν δεν ξανατρέχουν. Η εξαγωγή μένει διαθέσιμη για λήψη μέχρι να ολοκληρωθεί η διαγραφή.",
  keptAccounts: "{count} λογαριασμοί διατηρήθηκαν επειδή τους χρησιμοποιούν εγγραφές άλλου οργανισμού. Τους κρατούν:",
  workingBody: "Η επεξεργασία στο παρασκήνιο εκτελείται. Κάνε ανανέωση για να δεις την πρόοδο.",
  completedBody: "Ο οργανισμός διαγράφηκε. Η εγγραφή ελέγχου και το αρχείο διατήρησης παραμένουν.",
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
