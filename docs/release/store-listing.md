# Palee 3.0.0: store listing texts (App Store and Google Play)

> V3-M12 (CP-F1), ADR-256. Terms follow `docs/product/ontology.md` (Box, Μέλος box, Πακέτο συνδρομής, Τμήμα, WOD ημέρας, Προσωπικό, Ημερολόγιο, Club του box).
> Paste each block into the field named in its heading. Lengths in brackets were counted in characters (keywords in bytes); the table below shows each limit.
> Never write "Tap to Pay on iPhone" or use Apple's or Google's logos. Never mention prices, other platforms or "cheaper on the web" (ADR-256).

| Field | Store | Limit |
|---|---|---|
| App name | Apple | 30 |
| Subtitle | Apple | 30 |
| Promotional text | Apple | 170 (can change without a new build) |
| Keywords | Apple | 100 bytes, comma-separated, no spaces after commas; Greek letters count 2 bytes each |
| Description | Apple, Google | 4000 |
| What's New | Apple (not shown for the first version) | 4000 |
| Title | Google | 30 |
| Short description | Google | 80 |
| Release notes | Google | 500 per language |

Shared settings:

- **Primary language:** Greek (App Store Connect), Greek (el-GR) default in Play Console; English (en-US and en-GB) as a second localization.
- **Category:** Apple: Health & Fitness (primary), Lifestyle (secondary). Google: Health & Fitness.
- **Price:** free, no in-app purchases (ADR-256: payments go to the box through its provider).
- **Support URL / website:** `https://palee.app`, support email `support@palee.app`.
- **Privacy policy URL:** `https://palee.app/privacy` (page still to be published, see store-review-notes.md, open items).
- **Account deletion URL (Google):** `https://palee.app/me/settings#delete-account`.
- **Copyright (Apple):** `2026 <legal name of the Palee company>`.

---

## Ελληνικά (el)

### Όνομα (Apple)
```
Palee
```

### Υπότιτλος (Apple, 24)
```
Box, WOD και η παρέα σου
```

### Τίτλος (Google, 25)
```
Palee: Box, WOD και παρέα
```

### Σύντομη περιγραφή (Google, 75)
```
Κλείσε θέση, δες το WOD, γράψε το σκορ σου, μείνε κοντά στην παρέα του box.
```

### Keywords (Apple, 72 bytes)
Οι λέξεις του ονόματος και του υπότιτλου μετράνε ήδη, γι' αυτό δεν επαναλαμβάνονται.
```
crossfit,gym,κράτηση,hyrox,προπόνηση,pr,coach,τμήμα
```

### Promotional text (Apple)
```
Νέο: πλήρωσε το Πακέτο συνδρομής σου online, υπόγραψε έγγραφα του box από το κινητό και δες το WOD στην οθόνη του box.
```

### Περιγραφή (Apple και Google)
```
Η προπόνησή σου, το box σου, η παρέα σου. Όλα σε μία εφαρμογή.

Το Palee είναι η εφαρμογή για όσους προπονούνται σε CrossFit box, functional, HYROX, πολεμικές τέχνες ή στούντιο. Κλείνεις θέση στο τμήμα σου σε δύο πατήματα, βλέπεις το WOD ημέρας πριν φτάσεις και γράφεις το σκορ σου όταν τελειώσεις.

ΓΙΑ ΤΑ ΜΕΛΗ BOX
• Κράτηση και ακύρωση σε τμήματα, με λίστα αναμονής
• Το WOD ημέρας με κλίμακες για κάθε επίπεδο
• Σκορ, PR και ιστορικό στο προσωπικό σου Ημερολόγιο, που σε ακολουθεί σε όποιο box κι αν πας
• Πληρωμή του Πακέτου συνδρομής με κάρτα και αποδείξεις στο κινητό
• Check-in με QR στην είσοδο
• Το club του box: ανακοινώσεις, κανάλια, εκδηλώσεις, challenges
• Συνομιλίες με τον coach και με τα φιλαράκια σου
• Σύνδεση με Apple Health, Health Connect και Garmin, ώστε όλες οι προπονήσεις σου να είναι σε ένα σημείο
• Widgets στην αρχική οθόνη για τη σημερινή προπόνηση

ΓΙΑ ΤΟ ΠΡΟΣΩΠΙΚΟ ΤΟΥ BOX
• Πρόγραμμα τμημάτων, κρατήσεις και παρουσίες
• Πακέτα συνδρομής, πληρωμές online και στο ταμείο, νόμιμα παραστατικά
• Έγγραφα με ηλεκτρονική υπογραφή και βεβαιώσεις υγείας με υπενθύμιση λήξης
• WOD ημέρας για όλα τα τμήματα και οθόνη για την τηλεόραση του box με leaderboard

ΙΔΙΩΤΙΚΟ ΑΠΟ ΤΗΝ ΑΡΧΗ
Οι σημειώσεις, τα σωματικά στοιχεία και οι φωτογραφίες σου είναι ιδιωτικά, εκτός αν αποφασίσεις αλλιώς. Δεν υπάρχουν διαφημίσεις και δεν πουλάμε δεδομένα.

Το Palee χρειάζεται λογαριασμό. Οι πληρωμές πηγαίνουν κατευθείαν στο box σου, μέσω του παρόχου πληρωμών του.

Πολιτική απορρήτου: https://palee.app/privacy
Όροι χρήσης: https://palee.app/terms
```

### Τι νέο υπάρχει (What's New / Google release notes) για την 3.0.0
```
Η πρώτη έκδοση του Palee στα κινητά: κράτηση σε τμήματα, WOD ημέρας, σκορ και PR στο Ημερολόγιό σου, πληρωμή του Πακέτου συνδρομής, check-in με QR, το club του box και widgets στην αρχική οθόνη.
```

---

## English (en-US, en-GB)

### Name (Apple)
```
Palee
```

### Subtitle (Apple, 29)
```
Your box, your WOD, your crew
```

### Title (Google, 27)
```
Palee: Box, WOD & community
```

### Short description (Google, 74)
```
Book classes, see the WOD, log your score and stay close to your box crew.
```

### Keywords (Apple, 96 bytes)
```
crossfit,gym,booking,workout,hyrox,training log,pr,coach,class,fitness,functional,schedule,timer
```

### Promotional text (Apple)
```
New: pay for your subscription package online, sign your box's documents on your phone and see the WOD on the box screen.
```

### Description (Apple and Google)
```
Your training, your box, your crew. All in one app.

Palee is the app for people who train at a CrossFit box, functional gym, HYROX, martial-arts school or studio. Book your class in two taps, see the day's WOD before you arrive, and log your score when you finish.

FOR BOX MEMBERS
• Book and cancel classes, with a waiting list
• The day's WOD, scaled for every level
• Scores, PRs and history in your personal journal that follows you to any box
• Pay for your subscription package by card and keep receipts on your phone
• QR check-in at the door
• Your box's club: announcements, channels, events and challenges
• Chat with your coach and your buddies
• Connect Apple Health, Health Connect and Garmin so all your training is in one place
• Home-screen widgets for today's training

FOR BOX STAFF
• Class schedule, bookings and attendance
• Subscription packages, online and front-desk payments, legal receipts
• Documents with electronic signature, and health certificates with expiry reminders
• The day's WOD for every class, and a TV screen for the box with a live leaderboard

PRIVATE BY DEFAULT
Your notes, body data and photos are private unless you choose otherwise. No ads, and we never sell data.

Palee needs an account. Payments go straight to your box through its own payment provider.

Privacy policy: https://palee.app/privacy
Terms: https://palee.app/terms
```

### What's New / release notes for 3.0.0
```
The first mobile release of Palee: book classes, see the day's WOD, log scores and PRs in your journal, pay for your subscription package, check in with a QR code, follow your box's club and add home-screen widgets.
```

---

## Platform notes

- Apple shows "Apple Health" in the description; on Google Play, "Health Connect". Both appear above because one text is shared; if a reviewer objects, remove the other platform's name from that store's copy (Apple 2.3.10 forbids naming other mobile platforms in metadata; "Health Connect" is Android-only). **Safer default: in the App Store copy remove "Health Connect", in the Google Play copy remove "Apple Health".**
- Screenshots and their captions: `/mnt/project-files/milos/v3-store-release-prep.md` §16 (owner action: export from the demo business, real iPhone or simulator for the widget).
- Age rating answers: same notes, §8 (user-generated content yes, messaging yes, medical/wellness topics yes, AI yes; expected 13+ at Apple).
