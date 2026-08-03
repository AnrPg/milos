# Quick Text Workout DSL — Εγχειρίδιο Coach

Έκδοση DSL: **1**

Το Quick Text είναι ένας γρήγορος, document-like τρόπος συγγραφής workout.
Δεν δημιουργεί δεύτερο τύπο workout: το κείμενο μετατρέπεται στο ίδιο canonical
μοντέλο που χρησιμοποιεί το Structured mode. Το ακριβές κείμενο διατηρείται
για επόμενη επεξεργασία, αλλά η δημοσίευση, η ανάθεση και η εκτέλεση
χρησιμοποιούν αποκλειστικά το canonical workout.

## Τι εγγυάται το σύστημα

- Κάθε Preview και Publish γίνεται από τον authoritative backend parser.
- Λανθασμένο ή ημιτελές κείμενο αποθηκεύεται ως draft, αλλά δεν δημοσιεύεται.
- Τα errors πρέπει να διορθωθούν. Τα warnings πρέπει να ελεγχθούν και να
  επιβεβαιωθούν ρητά.
- Το Publish επαληθεύει την ακριβή revision του κειμένου. Παλιό browser tab δεν
  μπορεί να αντικαταστήσει ή να δημοσιεύσει νεότερη δουλειά.
- Πριν από την εγγραφή γίνεται δεύτερο canonical preflight και δοκιμαστική
  δημιουργία της timer sequence που θα δει ο αθλητής.
- Το Beautify εκτελείται μόνο σε έγκυρο κείμενο και δεν αλλάζει το νόημά του.
- Structured και Quick Text καταλήγουν στο ίδιο schema· η αλλαγή mode δεν
  χάνει canonical πληροφορία.

## Οι βασικοί κανόνες

1. Το έγγραφο αρχίζει με `[workout]` και τελειώνει με `[/workout]`.
2. Κάθε block ανοίγει με `[kind]` ή `[kind: value]` και κλείνει με `[/kind]`.
3. Κάθε παράμετρος γράφεται σε δική της γραμμή: `canonical-key: value`.
4. Τα blocks κλείνουν με αντίστροφη σειρά από αυτή με την οποία άνοιξαν.
5. Τα canonical keywords γράφονται με πεζά και kebab-case. Το autocomplete
   προτείνει την έγκυρη γραφή.
6. Τα ονόματα και οι σημειώσεις είναι κανονικό κείμενο και μπορούν να έχουν
   κενά και σημεία στίξης.
7. Κενές γραμμές επιτρέπονται μόνο για αναγνωσιμότητα.

```text
[workout]
dsl-version: 1
title: Friday strength and conditioning
type: strength
difficulty: all-levels
estimated-duration: 60m

[section: untimed]
title: Main strength
[exercise: Back Squat]
sets: 5
reps: 5
load: 75%1rm
rest-between-sets: 2m
!coach-note: Keep two repetitions in reserve.
[/exercise]
[/section]
[/workout]
```

## Μονάδες και τιμές

- Χρόνος: `30s`, `12m`, `1h`.
- Απόσταση: `500m`, `1.5km`.
- Απόλυτο φορτίο: `60kg`, `135lb`.
- Σχετικό φορτίο: `75%1rm`.
- Σωματικό βάρος: `bw`.
- Boolean: `true` ή `false`.
- Λίστα: τιμές χωρισμένες με κόμμα.
- Tempo: τετραψήφια canonical μορφή, π.χ. `31X1`.
- RPE/RIR, heart-rate zones και λοιπές αριθμητικές τιμές πρέπει να βρίσκονται
  στα όρια που εμφανίζει το inline diagnostic.

## Workout παράμετροι

Οι canonical παράμετροι είναι:

`dsl-version`, `canonical-schema-version`, `source-revision`, `title`,
`subtitle`, `description`, `type`, `difficulty`, `estimated-duration`,
`equipment`, `tags`, `target-population`, `objective`, `location`, `modality`,
`program-position`, `default-scale`, `is-team-workout`.

Το `type` ακολουθεί τους υπάρχοντες τύπους workout της εφαρμογής. Το
`source-revision` είναι metadata του προγράμματος· δεν αντικαθιστά την
αυτόματη revision ασφαλείας του draft.

## Notes

Οι σημειώσεις έχουν σκοπό και ορατότητα:

- `!note:` γενική σημείωση που μπορεί να δει ο αθλητής.
- `!coach-note:` ιδιωτική οδηγία προπονητή.
- `!athlete-note:` οδηγία γραμμένη ειδικά για τον αθλητή.
- `!safety-note:` κρίσιμη οδηγία ασφάλειας.
- `!scaling-note:` γενική οδηγία scaling.
- `!equipment-note:` διευκρίνιση εξοπλισμού.

Οι markers επιτρέπονται στα scopes που προσφέρει το contextual autocomplete.
Το σύστημα φιλτράρει server-side τα coach-only notes από athlete responses.

## Headers, groups και nested sections

Το `[header]` είναι οπτικός τίτλος μέσα σε section και δεν εκτελείται:

```text
[header]
title: Accessories
subtitle: Controlled quality work
[/header]
```

Τα groups είναι canonical compositions δύο ή περισσότερων exercises:

```text
[group: superset]
title: Upper body A
sets: 4
rest-between-groups: 90s
[exercise: Bench Press]
reps: 8
load: 70%1rm
[/exercise]
[exercise: Pull Up]
reps: 8
load: bw
[/exercise]
[/group]
```

Υποστηρίζονται `superset` και `alternating`. Ένα exercise δεν μπορεί να ανήκει
ταυτόχρονα και στα δύο. Sections μπορούν να περιέχουν nested sections· το
execution order είναι depth-first και ακολουθεί την οπτική σειρά.

## Exercises και prescriptions

Το όνομα στο `[exercise: ...]` πρέπει να είναι canonical catalog name ή ακριβές
καταχωρημένο alias. Δεν γίνεται fuzzy αντιστοίχιση στο Publish. Το autocomplete
χρησιμοποιεί το versioned catalog με stable IDs, aliases, categories και
capabilities.

Κύριες παράμετροι:

`sets`, `reps`, `duration`, `calories`, `distance`, `load`, `load-mode`,
`percentage-of`, `target-rpe`, `target-rir`, `tempo`, `pace`, `cadence`,
`target-heart-rate`, `side`, `stance`, `grip`, `range-of-motion`, `height`,
`incline`, `resistance`, `equipment`, `variation`, `interval-assignment`,
`score-contribution`, `transition-time`, όλα τα canonical rest fields,
`progression`, `load-start`, `load-step`, `prescription`, `excluded`.

Ένα uniform prescription:

```text
[exercise: Deadlift]
sets: 4
reps: 6
load: 100kg
tempo: 31X1
target-rpe: 8
rest-between-sets: 2m
[/exercise]
```

### Linear progression ή deload

```text
progression: linear
sets: 5
reps: 5
load-start: 60kg
load-step: +5kg
```

Για linear deload χρησιμοποιείται αρνητικό step, π.χ. `load-step: -5kg`.
Το canonical model αποθηκεύει και την πρόθεση progression και τα συγκεκριμένα
per-set prescriptions που θα εκτελεστούν.

### Arbitrary progression ανά set

```text
progression: explicit
sets:
- 5 reps @ 60kg
- 5 reps @ 70kg
- 3 reps @ 80kg
- 5 reps @ 70kg
- 8 reps @ 55kg
```

Οι explicit set γραμμές μπορούν να περιέχουν τα επιτρεπτά per-set metadata που
προσφέρει το autocomplete, όπως tempo, effort target, rest και note. Ο αριθμός
των γραμμών πρέπει να συμφωνεί με τον canonical αριθμό sets.

## Scales

Scale override μπαίνει μέσα στο exercise:

```text
[scale: beginner]
variation: Goblet Squat
sets: 4
reps: 8
load: 16kg
!scaling-note: Choose a load that preserves depth.
[/scale]
```

Το slug πρέπει να αντιστοιχεί σε ενεργό scale level. Με `excluded: true` το
exercise αφαιρείται από εκείνο το scale. Τα overrides μπορούν να αλλάξουν
exercise variation, prescription, progression, rest και τα επιτρεπτά
prescription metadata χωρίς να δημιουργούν δεύτερο workout.

## Όλα τα section formats

| Format | Υποχρεωτικά settings | Συνήθη scores |
|---|---|---|
| `untimed` | κανένα | load, reps, weight, pass_fail |
| `for-time` | κανένα | time |
| `train-to-exhaustion` | κανένα | reps, rounds, intervals_survived |
| `kcal-target` | `calorie-target` | time, kcal |
| `emom` | `duration`, `interval` | reps, rounds, pass_fail |
| `complex-emom` | `duration`, `interval` | reps, rounds, rounds+reps |
| `even-odd` | `duration` | reps, rounds, pass_fail |
| `billat` | `work`, `rest`, `cycles` | intervals_survived, accumulated_work_time, distance |
| `amrap` | `duration` | rounds, rounds+reps, reps |
| `edt` | `duration` | reps, rounds |
| `death-by` | `start-reps`, `step-reps` | intervals_survived, reps |
| `tabata` | `work`, `rest`, `rounds` | reps, pass_fail |
| `custom-hiit` | `work`, `rest`, `rounds` | reps, rounds, pass_fail |
| `cluster` | `intra-set-rest`, `sets` | load, reps |
| `hrr` | `effort-duration` | hr_drop, time |
| `ladder-ascending` | `start-reps`, `step-reps` | time, reps, rounds |
| `ladder-descending` | `start-reps`, `step-reps`, `minimum-reps` | time, reps, rounds |
| `pyramid` | `peak-reps`, `step-reps` | time, reps, rounds |
| `rest` | duration ή recovery condition | κανένα |

Το autocomplete και το template picker εμφανίζουν μόνο τα settings που
επιτρέπονται για το συγκεκριμένο format. Τα aliases `straight-sets`, `rounds`,
`circuit`, `stations` και `recovery` γίνονται canonical από το Beautify.

## Rest model

Υποστηρίζονται διαφορετικές σημασίες rest:

`rest-between-reps`, `rest-within-cluster`, `rest-between-sets`,
`rest-between-exercises`, `rest-between-rounds`, `rest-between-groups`,
`rest-between-sides`, `rest-after-exercise`, `rest-before-next-section`,
`rest-until`, `rest-range`, και dedicated `[section: rest]`.

Fixed rest δημιουργεί countdown. Rest με `recovery-condition` χωρίς διάρκεια
δημιουργεί manual recovery step ώστε να μην επινοείται χρόνος.

## Score και timer settings

Το `score` πρέπει να είναι συμβατό με το format. Προαιρετικά χρησιμοποιούνται
`score-unit` και `score-label`. Format-specific timer keys —όπως
`time-cap`, `maximum-windows`, `target-rounds`, `scoring-mode`,
`amrap-scoring-style`, `heart-rate-zone`, `heart-rate-drop-target`,
`recovery-cap`, `target-distance`, `target-pace`, `transition-time`— γίνονται
δεκτά μόνο στα formats που τα δηλώνουν.

Άγνωστο ή ασύμβατο setting είναι error, όχι metadata που αγνοείται.

## Editor, autocomplete και ασφάλεια

Το editor μοιάζει με κοινό document editor: headings, emphasis, lists, links,
undo/redo και paste. Η μορφοποίηση είναι presentation cache· το plain canonical
DSL text παραμένει η σημασιολογική πηγή.

Το contextual dropdown ενημερώνεται καθώς γράφει ο coach και χωρίζει:

1. structural suggestions από canonical vocabulary, active scales, enums,
   μονάδες, formats και exercise catalog,
2. non-semantic common words για τίτλους και notes.

Μόνο η πρώτη κατηγορία δημιουργεί semantics. Common-word completion δεν
μετατρέπει ποτέ μια πρόταση σε parameter. Το draft δεν αποστέλλεται σε
third-party writing service.

Paste content καθαρίζεται από scripts, embedded objects, event handlers και
επικίνδυνα URLs. Υπάρχουν όρια μεγέθους, βάθους nesting, αριθμού blocks και
diagnostics ώστε malformed input να μην εξαντλεί τον server.

## Προτεινόμενη ροή coach

1. Διάλεξε full-workout ή section template.
2. Γράψε με autocomplete αντί να απομνημονεύεις keywords.
3. Παρακολούθησε τα inline diagnostics.
4. Πάτησε Preview και έλεγξε το canonical αποτέλεσμα.
5. Πάτησε Beautify για ομοιόμορφη τελική εμφάνιση.
6. Έλεγξε κάθε warning.
7. Κάνε Publish. Αν έχει αλλάξει το draft αλλού, κάνε reload και σύγκρινε πριν
   συνεχίσεις.

Η canonical vocabulary, τα 19 templates, το in-app manual και ο parser
παράγονται από το ίδιο versioned registry. Αλλαγή στη γλώσσα απαιτεί νέα
version, fixtures, round-trip tests και ενημέρωση αυτού του εγχειριδίου.
