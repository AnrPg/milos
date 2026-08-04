# TrainingJournal - Οδηγός SaaS Provider και Onboarding Πελατών

## Σκοπός

Αυτό το έγγραφο περιγράφει πώς λειτουργεί το TrainingJournal ως SaaS προϊόν για
πολλά ανεξάρτητα γυμναστήρια ή coaching businesses, ποιος κάνει κάθε ενέργεια και
ποια βήματα πρέπει να ακολουθεί ένας νέος πελάτης για να μπει σωστά στην
πλατφόρμα.

Το TrainingJournal είναι το όνομα του προϊόντος και της πλατφόρμας. Το Milos
Training δεν είναι πλέον το όνομα της εφαρμογής συνολικά. Είναι ένα γυμναστήριο,
δηλαδή ένας πελάτης/tenant μέσα στην πλατφόρμα.

## Βασικές έννοιες

### Platform owner

Ο platform owner είναι ο πάροχος του TrainingJournal. Έχει ευθύνη για:

- δημιουργία νέων organizations,
- αρχική πρόσκληση του owner κάθε γυμναστηρίου,
- αναστολή ή αρχειοθέτηση ενός πελάτη,
- backup, restore, export και operational audit,
- διαχείριση product-level ρυθμίσεων,
- προστασία tenant isolation.

Το platform-owner δικαίωμα είναι εγκαταστασιακό δικαίωμα. Δεν είναι το ίδιο με το
να είσαι owner ενός γυμναστηρίου.

### Organization / tenant

Κάθε γυμναστήριο είναι ένα `organization`. Το organization έχει δικό του:

- όνομα,
- slug για routes τύπου `/org/:organization_slug`,
- timezone,
- default locale,
- προσκλήσεις εγγραφής,
- memberships και ρόλους,
- branding,
- tenant-owned δεδομένα.

Παράδειγμα: το Milos Training πρέπει να είναι organization όπως κάθε άλλος
πελάτης, όχι το global app brand.

### Gym owner

Ο gym owner είναι ο ιδιοκτήτης ενός συγκεκριμένου organization. Μπορεί να
διαχειρίζεται το γυμναστήριό του, αλλά δεν πρέπει να μπορεί να δημιουργεί ή να
διαχειρίζεται άλλα organizations στην εγκατάσταση.

### Member, athlete, coach, admin

Οι ρόλοι αυτοί πρέπει να είναι membership-scoped. Δηλαδή ένας χρήστης μπορεί να
είναι coach στο ένα γυμναστήριο και απλό μέλος σε άλλο. Η παλιά ιδέα ενός global
`user.role` πρέπει να θεωρείται μεταβατική συμβατότητα, όχι πηγή αλήθειας.

### Product brand και tenant brand

Υπάρχουν δύο διαφορετικά επίπεδα branding:

1. Product brand: `TrainingJournal`.
2. Tenant brand: το brand κάθε γυμναστηρίου, π.χ. `Milos Training`, `North Harbor
   Strength`, `Athens Barbell Club`.

Σε προσωπικές ή platform-level οθόνες χωρίς tenant context εμφανίζεται
`TrainingJournal`. Σε tenant-scoped οθόνες εμφανίζεται το brand του γυμναστηρίου.

## Πού πρέπει να εμφανίζεται κάθε brand

### TrainingJournal

Το TrainingJournal πρέπει να εμφανίζεται σε:

- login και γενικές auth οθόνες πριν ο χρήστης επιλέξει organization,
- personal Journal/Today/Progress εμπειρία όταν δεν υπάρχει tenant context,
- browser/PWA metadata που αφορά το προϊόν συνολικά,
- platform-owner dashboard,
- τεχνικά emails ή system notices που δεν ανήκουν σε συγκεκριμένο γυμναστήριο,
- API/documentation/operator guides.

### Brand γυμναστηρίου

Το brand του γυμναστηρίου πρέπει να εμφανίζεται σε:

- organization selector,
- `/org/:slug` user surfaces,
- admin surfaces που αφορούν το συγκεκριμένο organization,
- class schedule,
- workout assignment/coaching flows,
- tenant-specific notifications,
- receipts/invoices για το συγκεκριμένο gym,
- tenant exports,
- share/export documents που δημιουργούνται μέσα από tenant context.

### Fallback σειρά

Όταν η UI χρειάζεται tenant brand, η σειρά πρέπει να είναι:

1. `organization_settings.brand_name`, αν υπάρχει.
2. `organizations.name`.
3. `TrainingJournal`, μόνο αν δεν υπάρχει tenant context ή αν τα tenant settings
   λείπουν λόγω σφάλματος.

Το `Legacy Milos Training` δεν πρέπει να χρησιμοποιείται ως γενικό fallback brand.

## Τρέχουσα κατάσταση λογισμικού

Η πλατφόρμα έχει ήδη βασικά multi-tenant primitives:

- `organizations`,
- `organization_memberships`,
- `organization_settings`,
- `registration_invitations`,
- tenant context σε routes `/org/:organization_slug`,
- platform provisioning οθόνη στο `/platform/organizations`,
- lifecycle states `active`, `suspended`, `archived`,
- staged tenant isolation και RLS enforcement.

Υπάρχουν ήδη πεδία branding σε organization settings:

- `brand_name`,
- `brand_logo_url`,
- `brand_primary_color`.

Σημαντική λεπτομέρεια: το τρέχον UI αποθηκεύει URL λογοτύπου. Για πραγματικό upload
αρχείου από τον gym owner χρειάζεται ξεχωριστή ροή upload με tenant-scoped object
storage, validation, preview και audit. Μέχρι να προστεθεί αυτή η ροή, ο operator
μπορεί να χρησιμοποιεί ασφαλές URL λογοτύπου που δείχνει σε εγκεκριμένο asset.

## Τι είναι το `Legacy Milos Training`

Το `Legacy Milos Training` είναι μεταβατικό organization που δημιουργήθηκε για να
μη μείνουν τα προϋπάρχοντα δεδομένα χωρίς `organization_id` κατά τη μετάβαση σε
multi-tenancy.

Δεν είναι:

- το όνομα του SaaS προϊόντος,
- ειδικό super-tenant,
- global default για όλους,
- κάτι που πρέπει να βλέπουν νέοι πελάτες.

Είναι:

- σταθερό legacy tenant με slug `legacy-milos-training`,
- anchor για παλιά tenant-owned rows,
- εργαλείο ασφαλούς staged migration,
- προσωρινό label που πρέπει να προαχθεί/μετονομαστεί όταν ολοκληρωθεί ο audit.

Αν εμφανίζεται στον organization selector, σημαίνει ότι ο συνδεδεμένος χρήστης έχει
active membership σε αυτό το organization. Αυτό είναι σωστό τεχνικά, αλλά όχι
ιδανικό ως product experience.

## Μπορεί το Legacy Milos Training να μεταφερθεί στο νέο μοντέλο;

Ναι. Η προτεινόμενη στρατηγική δεν είναι να φτιαχτεί δεύτερο Milos tenant και να
γίνει copy όλων των δεδομένων. Η ασφαλέστερη στρατηγική είναι να προαχθεί το ήδη
υπάρχον legacy organization σε κανονικό client tenant.

Πρακτικά αυτό σημαίνει:

- το organization παραμένει το ίδιο record,
- το slug μπορεί να μείνει `legacy-milos-training` προσωρινά ή να αλλάξει σε
  `milos-training` μόνο με ελεγχόμενη migration,
- το display name γίνεται `Milos Training`,
- το `brand_name` γίνεται `Milos Training`,
- προστίθεται σωστό logo/brand color,
- ελέγχονται memberships και roles,
- επιβεβαιώνεται ότι όλα τα tenant-owned rows δείχνουν σε αυτό το organization,
- τα global personal rows μένουν προσωπικά και δεν μεταφέρονται στον tenant.

## Συνέπειες και caveats της μεταφοράς

### Tenant isolation

Πριν μπει δεύτερος πραγματικός πελάτης σε production, πρέπει να έχει περάσει ο
tenancy audit. Αν υπάρχουν ακόμα routes, jobs, cache keys ή projections που
υποθέτουν legacy/global organization, υπάρχει κίνδυνος διαρροής δεδομένων μεταξύ
πελατών.

### Personal history

Το personal Journal, προσωπικά PRs, self-authored wellbeing facts και private notes
δεν πρέπει να γίνουν ιδιοκτησία του Milos tenant απλώς επειδή δημιουργήθηκαν πριν
το multi-tenancy. Μπορούν να έχουν organization provenance ή sharing grants, αλλά
η ιδιοκτησία παραμένει στον χρήστη.

### Links και bookmarks

Αν αλλάξει το slug από `legacy-milos-training` σε `milos-training`, παλιά links τύπου
`/org/legacy-milos-training/...` μπορεί να σπάσουν αν δεν υπάρχει redirect ή alias.
Για production, καλύτερα να κρατηθεί το παλιό slug μέχρι να προστεθεί canonical
redirect/alias strategy.

### Cache, search και materialized views

Μετά από rename/settings αλλαγές πρέπει να καθαριστούν ή να ανανεωθούν:

- React Query/browser caches,
- Redis tenant cache keys,
- Meilisearch documents,
- analytics projections,
- coaching aggregates,
- leaderboard/materialized views όπου χρησιμοποιούν tenant metadata.

### Object storage

Παλιά invoice/avatar/document keys μπορεί να δείχνουν σε legacy paths. Πρέπει να
τρέχει πρώτα dry-run και μετά apply για legacy object migration, με checksum
verification. Δεν πρέπει να μετακινούνται objects με manual SQL updates.

### Notifications και exports

Υπάρχουν ακόμα product strings που αναφέρουν `Milos Training` σε push defaults,
calendar text, exported documents, PWA manifest και translations. Αυτά πρέπει να
μεταφερθούν σε:

- `TrainingJournal` για product-level fallback,
- tenant brand για tenant-scoped notification/export/calendar surfaces.

### Audit history

Η προώθηση του legacy tenant πρέπει να αφήνει audit trail. Πρέπει να είναι σαφές
πότε το legacy record έγινε κανονικός Milos client tenant και ποιος operator το
ενέκρινε.

### Billing και offboarding

Αν το Milos γίνει κανονικός πελάτης, ισχύουν οι ίδιοι κανόνες lifecycle με όλους:

- `active` για κανονική χρήση,
- `suspended` για προσωρινό πάγωμα πρόσβασης,
- `archived` για offboarding,
- όχι hard delete χωρίς export, retention review και ξεχωριστή εγκεκριμένη
  destructive διαδικασία.

## Βήματα provider για νέο πελάτη

### 1. Προετοιμασία

Πριν δημιουργηθεί νέος πελάτης:

1. Επιβεβαίωσε ότι το runtime DB role δεν είναι superuser και δεν έχει `BYPASSRLS`.
2. Τρέξε tenancy audit.
3. Τρέξε architecture gate.
4. Επιβεβαίωσε ότι backups δουλεύουν.
5. Επιβεβαίωσε ότι το object storage έχει tenant-scoped prefixes.
6. Συμφώνησε με τον πελάτη σε όνομα, slug, timezone, locale και αρχικό owner.

### 2. Platform-owner bootstrap

Αν δεν υπάρχει platform owner:

```bash
cd apps/api
mix milos.platform.grant_owner NICKNAME
```

Το `NICKNAME` είναι υπάρχων χρήστης. Αυτός ο χρήστης αποκτά εγκαταστασιακή εξουσία.
Δεν πρέπει να είναι απλός gym owner πελάτη.

### 3. Δημιουργία organization

Ο platform owner ανοίγει:

```text
/platform/organizations
```

Συμπληρώνει:

- legal/client name,
- slug,
- timezone,
- default locale,
- invitation lifetime,
- brand name,
- brand logo URL ή εγκεκριμένο logo asset,
- primary color.

Μετά πατά provision.

### 4. Αρχική πρόσκληση owner

Το σύστημα επιστρέφει one-time owner invitation token. Ο operator πρέπει:

1. Να το αντιγράψει αμέσως.
2. Να το στείλει από ιδιωτικό/εγκεκριμένο κανάλι.
3. Να μην το αποθηκεύσει σε plain text.
4. Να ζητήσει από τον πελάτη να το εξαργυρώσει πριν λήξει.

Automated email/OTP delivery δεν είναι ακόμα υλοποιημένο.

### 5. Έλεγχος πρώτης σύνδεσης

Ο πελάτης πρέπει να:

1. Ανοίξει το invitation link.
2. Δημιουργήσει ή συνδέσει λογαριασμό.
3. Επιβεβαιώσει ότι βλέπει το σωστό organization.
4. Ανοίξει το canonical path `/org/:slug`.
5. Ελέγξει brand name, logo, χρώμα, locale και timezone.

### 6. Ρύθμιση ομάδας πελάτη

Ο gym owner προσκαλεί ή ζητά από τον provider να προσκαλέσει:

- coaches,
- admins,
- members,
- athletes.

Κάθε πρόσκληση πρέπει να αντιστοιχεί σε συγκεκριμένο role και συγκεκριμένο
organization. Ένας χρήστης δεν πρέπει να αποκτά global admin δικαίωμα για να
διαχειρίζεται ένα γυμναστήριο.

### 7. Αρχική λειτουργική παραμετροποίηση

Ο gym owner πρέπει να ελέγξει:

- class types,
- weekly schedule,
- booking rules,
- workout scale levels,
- workout library folders,
- finance packages,
- membership defaults,
- notifications/push setup,
- coaching assignment workflow,
- receipt/invoice mode,
- language και timezone.

### 8. Go-live checklist

Πριν ο πελάτης χρησιμοποιήσει production:

- ο owner μπορεί να μπει,
- ένας coach μπορεί να μπει,
- ένα member μπορεί να μπει,
- ένας athlete μπορεί να μπει,
- κάθε ρόλος βλέπει μόνο το δικό του tenant,
- το `/org/:slug` δουλεύει μετά από refresh,
- η αλλαγή organization δεν διαρρέει δεδομένα,
- notifications έχουν σωστό brand,
- calendar exports έχουν σωστό brand,
- invoices/receipts έχουν σωστό brand,
- logo εμφανίζεται σε tenant surfaces,
- backup και restore drill έχουν καταγραφεί.

## Βήματα που πρέπει να κάνει ο πελάτης

Ο πελάτης, δηλαδή ο gym owner, πρέπει να δώσει στον provider:

1. Επίσημο όνομα γυμναστηρίου.
2. Επιθυμητό app/display name.
3. Επιθυμητό slug.
4. Timezone.
5. Κύρια γλώσσα.
6. Logo σε ασφαλή μορφή.
7. Primary brand color.
8. Email ή nickname αρχικού owner.
9. Λίστα πρώτων coaches/admins.
10. Βασικά πακέτα/τιμοκατάλογο, αν θα χρησιμοποιηθεί Finance.
11. Βασικά class types.
12. Πολιτική κρατήσεων και ακυρώσεων.

Μετά την πρόσκληση πρέπει:

1. Να εξαργυρώσει το invitation.
2. Να επιβεβαιώσει ότι εμφανίζεται το σωστό brand.
3. Να αλλάξει τυχόν λάθος timezone/locale μέσω provider αν δεν έχει self-service
   δικαίωμα.
4. Να προσκαλέσει ή να ζητήσει πρόσκληση για το προσωπικό.
5. Να δοκιμάσει μία class booking ροή.
6. Να δοκιμάσει ένα workout assignment.
7. Να ελέγξει notifications και receipts.
8. Να αναφέρει λάθος δεδομένα πριν μπει κανονική χρήση.

## Branding requirements για gym owners

Κάθε gym owner πρέπει τελικά να μπορεί να ορίζει:

- tenant display/app name,
- logo,
- primary color,
- locale,
- timezone,
- invitation lifetime ή σχετική πολιτική onboarding.

Το logo upload πρέπει να:

- αποθηκεύεται κάτω από tenant-scoped object key,
- ελέγχει τύπο αρχείου,
- ελέγχει μέγεθος,
- αποφεύγει SVG αν δεν υπάρχει ασφαλής sanitizer,
- κρατά audit event,
- παρέχει preview,
- επιτρέπει αντικατάσταση χωρίς να σπάει παλιά exports,
- μην επιτρέπει σε owner ενός tenant να γράψει asset άλλου tenant.

## Προτεινόμενη μετάβαση του Milos

Για το υπάρχον Milos:

1. Κράτα το existing legacy organization record.
2. Άλλαξε display name από `Legacy Milos Training` σε `Milos Training`.
3. Θέσε `brand_name = "Milos Training"`.
4. Πρόσθεσε σωστό logo και primary color.
5. Έλεγξε ότι οι Milos users έχουν σωστά organization memberships.
6. Τρέξε tenancy audit.
7. Τρέξε object migration dry-run.
8. Τρέξε object migration apply μόνο μετά από backup.
9. Αναγέννησε search/cache/projections όπου χρειάζεται.
10. Μην αλλάξεις slug μέχρι να υπάρχει redirect/alias plan.

Το αποτέλεσμα είναι ότι το Milos γίνεται κανονικός πελάτης του TrainingJournal,
χωρίς να χαθεί το ownership των legacy δεδομένων.

## Τι δεν πρέπει να γίνει

- Μην χρησιμοποιήσεις το `Legacy Milos Training` ως global app name.
- Μην δημιουργήσεις δεύτερο Milos organization χωρίς migration plan.
- Μην μεταφέρεις προσωπικά δεδομένα χρηστών σε tenant ownership.
- Μην κάνεις direct SQL updates σε tenant-owned records για να παρακαμφθούν
  changesets/RLS.
- Μην στείλεις invitation tokens σε δημόσια ή logged κανάλια.
- Μην επιτρέψεις σε gym owner να γίνει platform owner.
- Μην κάνεις hard delete tenant χωρίς export, retention review και ανθρώπινη
  έγκριση.

## Operational commands

Platform-owner grant:

```bash
cd apps/api
mix milos.platform.grant_owner NICKNAME
```

Tenancy audit:

```bash
cd apps/api
mix milos.tenancy.audit
```

Architecture gate:

```bash
cd apps/api
mix milos.architecture
```

Legacy object migration dry-run:

```bash
cd apps/api
mix milos.storage.migrate_legacy_objects
```

Legacy object migration apply:

```bash
cd apps/api
mix milos.storage.migrate_legacy_objects --apply
```

## Definition of done για SaaS readiness

Η πλατφόρμα είναι έτοιμη για πολλούς πελάτες όταν:

- το TrainingJournal εμφανίζεται μόνο ως product shell,
- κάθε tenant εμφανίζει δικό του brand,
- κανένα νέο client UI δεν δείχνει `Legacy Milos Training`,
- όλοι οι tenant-owned πίνακες έχουν enforced ownership,
- τα personal records παραμένουν user-owned,
- όλα τα routes απαιτούν σωστό tenant context όπου χρειάζεται,
- jobs, cache, search, storage και exports είναι tenant-aware,
- υπάρχει documented backup/restore/export διαδικασία,
- υπάρχει logo upload ή ασφαλής προσωρινή πολιτική logo URL,
- ο operator μπορεί να suspend/archive tenant χωρίς data loss.
