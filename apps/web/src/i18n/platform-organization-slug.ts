const en = {
  open: "Change slug",
  title: "Change organization slug",
  intro:
    "The slug is the organization's address: every workspace link lives under /org/{slug}. Renaming it moves the canonical path for everyone.",
  loading: "Loading impact summary...",
  loadError: "The impact summary could not be loaded.",
  currentPath: "Current path",
  newSlugLabel: "New slug",
  newSlugHelp: "3-63 lowercase letters, digits and single hyphens.",
  newPath: "New path",
  impactTitle: "What this changes",
  activeMembers: "{count} active members will move to the new path.",
  pendingInvitations: "{count} pending invitations keep working: invitation links carry a token, not the slug.",
  bookmarks:
    "Bookmarks, shared links and older notifications that use /org/{slug} keep working: they redirect to the new path.",
  reserved:
    "The current slug stays reserved for this organization, so no other organization can take it. You can switch back to it later.",
  previousSlugs: "Previous slugs (still redirecting)",
  purgeBlocked: "An export & purge request is open. Cancel it before changing the slug.",
  confirmationLabel: "Type {slug} to confirm",
  confirm: "Change slug",
  confirming: "Changing...",
  cancel: "Cancel",
  done: "The organization now lives at {path}.",
  close: "Close",
  invalidSlug: "Use 3-63 lowercase letters, digits and single hyphens.",
  unchanged: "The new slug matches the current one.",
  taken: "This slug belongs to another organization or is reserved as its previous slug.",
  mismatch: "Type the current slug exactly to confirm.",
  actionError: "The slug could not be changed.",
};

export type PlatformOrganizationSlugCopy = { [Key in keyof typeof en]: string };

const el: PlatformOrganizationSlugCopy = {
  open: "Αλλαγή slug",
  title: "Αλλαγή slug οργανισμού",
  intro:
    "Το slug είναι η διεύθυνση του οργανισμού: κάθε σύνδεσμος του χώρου εργασίας βρίσκεται κάτω από το /org/{slug}. Η μετονομασία του αλλάζει την κανονική διαδρομή για όλους.",
  loading: "Φόρτωση σύνοψης επιπτώσεων...",
  loadError: "Δεν ήταν δυνατή η φόρτωση της σύνοψης επιπτώσεων.",
  currentPath: "Τρέχουσα διαδρομή",
  newSlugLabel: "Νέο slug",
  newSlugHelp: "3-63 πεζά γράμματα, ψηφία και μονές παύλες.",
  newPath: "Νέα διαδρομή",
  impactTitle: "Τι αλλάζει",
  activeMembers: "{count} ενεργά μέλη θα μεταφερθούν στη νέα διαδρομή.",
  pendingInvitations:
    "{count} εκκρεμείς προσκλήσεις συνεχίζουν να λειτουργούν: οι σύνδεσμοι πρόσκλησης περιέχουν token, όχι το slug.",
  bookmarks:
    "Σελιδοδείκτες, κοινόχρηστοι σύνδεσμοι και παλαιότερες ειδοποιήσεις με /org/{slug} συνεχίζουν να λειτουργούν: ανακατευθύνονται στη νέα διαδρομή.",
  reserved:
    "Το τρέχον slug παραμένει δεσμευμένο για αυτόν τον οργανισμό, ώστε κανένας άλλος οργανισμός να μην μπορεί να το πάρει. Μπορείς να επιστρέψεις σε αυτό αργότερα.",
  previousSlugs: "Προηγούμενα slug (εξακολουθούν να ανακατευθύνουν)",
  purgeBlocked: "Υπάρχει ανοιχτό αίτημα εξαγωγής & εκκαθάρισης. Ακύρωσέ το πριν αλλάξεις το slug.",
  confirmationLabel: "Πληκτρολόγησε {slug} για επιβεβαίωση",
  confirm: "Αλλαγή slug",
  confirming: "Αλλαγή...",
  cancel: "Ακύρωση",
  done: "Ο οργανισμός βρίσκεται πλέον στο {path}.",
  close: "Κλείσιμο",
  invalidSlug: "Χρησιμοποίησε 3-63 πεζά γράμματα, ψηφία και μονές παύλες.",
  unchanged: "Το νέο slug είναι ίδιο με το τρέχον.",
  taken: "Αυτό το slug ανήκει σε άλλον οργανισμό ή είναι δεσμευμένο ως προηγούμενο slug του.",
  mismatch: "Πληκτρολόγησε ακριβώς το τρέχον slug για επιβεβαίωση.",
  actionError: "Δεν ήταν δυνατή η αλλαγή του slug.",
};

export function platformOrganizationSlugCopy(locale: string): PlatformOrganizationSlugCopy {
  return locale === "el" ? el : en;
}

export function formatSlugCopy(template: string, values: Record<string, string | number>) {
  return template.replace(/\{(\w+)\}/g, (match, key: string) =>
    key in values ? String(values[key]) : match,
  );
}
