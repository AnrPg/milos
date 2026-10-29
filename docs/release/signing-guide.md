# Οδηγός υπογραφής και ανεβάσματος των εφαρμογών Palee (iOS και Android)

> Για τον ANR. V3-M12 (CP-F1), ADR-256. Γραμμένος για κάποιον που **δεν** έχει ξαναβγάλει εφαρμογή σε store.
> Συμπληρώνει το `/mnt/project-files/milos/v3-store-release-prep.md` (λογαριασμοί, αποφάσεις, χρονοδιάγραμμα). Εδώ είναι το **πώς**: κάθε βήμα, κάθε εντολή, τι σημαίνει κάθε επιλογή, τι βγάζει και πού το ελέγχεις.
> Ό,τι γράφεται σε `κώδικα` το πληκτρολογείς όπως είναι. Ό,τι είναι σε `<γωνιακές αγκύλες>` το αντικαθιστάς με το δικό σου.
> Οι σελίδες της Apple και της Google αλλάζουν μενού συχνά. Αν ένα κουμπί δεν είναι εκεί που λέει ο οδηγός, ψάξε το όνομά του στη σελίδα βοήθειας που δίνεται στο τέλος κάθε ενότητας.

## Περιεχόμενα

1. Λεξιλόγιο: τι είναι υπογραφή, πιστοποιητικό, κλειδί
2. Τι χρειάζεσαι πριν ξεκινήσεις
3. Apple: App ID, δυνατότητες, κλειδί push, υπογραφή, ανέβασμα
4. Android: keystore (κλειδί ανεβάσματος), Play App Signing, ανέβασμα
5. Τα στοιχεία που πάνε στον server (Team ID, αποτυπώματα SHA-256)
6. Έλεγχος ότι τα links ανοίγουν την εφαρμογή
7. Αριθμοί έκδοσης και build
8. Ασφαλής φύλαξη: τι κρατάς, πού, και τι κάνεις αν χαθεί
9. Πού ψάχνεις όταν κάτι δεν πάει καλά

---

## 1. Λεξιλόγιο

Πριν από τα βήματα, οι λέξεις που θα συναντάς συνέχεια.

- **Υπογραφή (code signing).** Κάθε εφαρμογή που ανεβαίνει σε store είναι «υπογεγραμμένη»: ένα μαθηματικό αποτύπωμα του αρχείου, φτιαγμένο με ένα **ιδιωτικό κλειδί** που έχεις μόνο εσύ. Το store και το κινητό ελέγχουν την υπογραφή με το αντίστοιχο **δημόσιο κλειδί**. Έτσι ξέρουν ότι η εφαρμογή ήρθε από εσένα και ότι κανείς δεν την άλλαξε στο δρόμο.
- **Ιδιωτικό κλειδί / δημόσιο κλειδί.** Ζευγάρι. Ό,τι υπογράφει το ιδιωτικό, το επιβεβαιώνει το δημόσιο. Το δημόσιο το δίνεις σε όλους. Το ιδιωτικό **δεν** το δίνεις ποτέ, ούτε σε μένα, ούτε στο git.
- **Πιστοποιητικό (certificate).** Το δημόσιο κλειδί μαζί με το ποιος είσαι, «σφραγισμένο» από κάποιον που το εμπιστεύονται όλοι. Στο iOS τη σφραγίδα τη βάζει η Apple. Στο Android το πιστοποιητικό είναι «αυτο-υπογεγραμμένο» (το φτιάχνεις μόνος σου), και η Google απλώς θυμάται ποιο είναι.
- **Bundle id (Apple) / package name (Google).** Η μόνιμη ταυτότητα της εφαρμογής. Για το Palee: `app.palee.member`. Μετά το πρώτο ανέβασμα **δεν αλλάζει ποτέ**.
- **Team ID (Apple).** 10 χαρακτήρες (γράμματα και ψηφία, π.χ. `A1B2C3D4E5`) που ταυτοποιούν τον λογαριασμό σου στην Apple. Μπαίνει στον server για τα universal links.
- **App ID (Apple).** Η «καρτέλα» της εφαρμογής στον λογαριασμό developer: bundle id και οι δυνατότητες (push, Health κ.λπ.) που επιτρέπεται να χρησιμοποιεί.
- **Provisioning profile (Apple).** Ένα αρχείο που λέει «αυτή η εφαρμογή (App ID), υπογεγραμμένη με αυτό το πιστοποιητικό, επιτρέπεται να έχει αυτές τις δυνατότητες». Το Xcode το φτιάχνει μόνο του με την αυτόματη υπογραφή.
- **Keystore (Android).** Αρχείο (`.jks`) που κρατά ένα ή περισσότερα ιδιωτικά κλειδιά με το πιστοποιητικό τους, κλειδωμένα με κωδικό. Κάθε κλειδί μέσα στο keystore έχει ένα όνομα, το **alias**.
- **Upload key / App signing key (Android).** Με το **Play App Signing**, η Google κρατά το κλειδί που υπογράφει την εφαρμογή που κατεβάζουν οι χρήστες (*app signing key*). Εσύ κρατάς ένα δεύτερο κλειδί, το *upload key*, με το οποίο υπογράφεις ό,τι ανεβάζεις. Αν χάσεις το upload key, η Google σου επιτρέπει να βάλεις καινούργιο. Αν δεν υπήρχε αυτό το σύστημα και χανόταν το κλειδί, η εφαρμογή δεν θα ξαναενημερωνόταν ποτέ.
- **Αποτύπωμα SHA-256 (fingerprint).** Ένα «δακτυλικό αποτύπωμα» του πιστοποιητικού: 32 ζευγάρια δεκαεξαδικών ψηφίων με άνω και κάτω τελεία, π.χ. `14:6D:E9:…:B4`. Δημόσιο, όχι μυστικό. Μπαίνει στον server για να ανοίγουν τα links την εφαρμογή στο Android.
- **AAB (Android App Bundle).** Το αρχείο που ανεβάζεις στο Google Play (`.aab`). Από αυτό η Google φτιάχνει τα APK για κάθε κινητό.
- **Archive / IPA (iOS).** Το «πακέτο» της εφαρμογής iOS που φτιάχνει το Xcode και ανεβάζει στο App Store Connect.

---

## 2. Τι χρειάζεσαι πριν ξεκινήσεις

| Τι | Για ποιο | Πού το βρίσκεις |
|---|---|---|
| Λογαριασμός **Apple Developer Program** (99 USD/χρόνο) | iOS | https://developer.apple.com/programs/enroll/ (βλ. release-prep §2) |
| Λογαριασμός **Google Play Console** (25 USD μία φορά) | Android | https://play.google.com/console/signup |
| **Mac** με **Xcode 26** ή νεότερο | iOS | App Store του Mac. Από 28/4/2026 η Apple δέχεται μόνο builds με το SDK του iOS 26 |
| **Android Studio** (έχει μέσα Java 21 και το `keytool`) | Android | https://developer.android.com/studio |
| **Node.js 22** και το repo του Palee | και τα δύο | `node --version` πρέπει να δείχνει `v22…` ή νεότερο |
| **Password manager** (1Password, Bitwarden, KeePassXC) | φύλαξη | Εδώ μπαίνουν όλοι οι κωδικοί και τα αρχεία κλειδιών |

Πρώτη προετοιμασία του project (μία φορά σε κάθε υπολογιστή που χτίζει):

```sh
cd apps/mobile
npm run bootstrap
```

- `cd apps/mobile`: πηγαίνεις στον φάκελο των εφαρμογών κινητού.
- `npm run bootstrap`: τρέχει το `scripts/bootstrap.sh`, που (1) εγκαθιστά ακριβώς τις εκδόσεις του Capacitor από το `package-lock.json` (`npm ci`), (2) γράφει στα native projects το URL του `palee.app`, τα app links, την έκδοση `3.0.0` και τον αριθμό build (`scripts/configure.mjs`), (3) τρέχει `npx cap sync`, που αντιγράφει τα plugins στα projects iOS και Android.
- **Τι βγάζει:** στο τέλος γράφει `Palee production: https://palee.app (app.palee.member) 3.0.0 (1)` και μια λίστα `updated …`. Αν λείπει το `google-services.json` γράφει μια σημείωση (το push του Android μένει κλειστό ως το βήμα 4.6).
- **Μεταβλητές που αλλάζουν τη συμπεριφορά** (τις γράφεις μπροστά από την εντολή, π.χ. `PALEE_BUILD_NUMBER=2 npm run bootstrap`):

| Μεταβλητή | Τι κάνει | Default |
|---|---|---|
| `PALEE_APP_ENV` | `production`, `staging` ή `development` | `production` |
| `PALEE_APP_URL` | Άλλο URL αντί για του περιβάλλοντος | το URL του περιβάλλοντος (`https://palee.app`) |
| `PALEE_APS_ENVIRONMENT` | Περιβάλλον push του iOS: `production` ή `development` | `production` (εκτός από `development`) |
| `PALEE_BUILD_NUMBER` | Αριθμός build για αυτό το ανέβασμα (§7) | ό,τι λέει το `config/release.json` |

---

## 3. Apple

### 3.1 Βρες το Team ID

1. Μπες στο https://developer.apple.com/account.
2. Κάτω από **Membership details** δες το **Team ID** (10 χαρακτήρες).
3. Γράψ' το στον password manager με τίτλο «Palee Apple Team ID». Δεν είναι μυστικό, αλλά θα το χρειαστείς τρεις φορές.

### 3.2 Φτιάξε το App ID με τις δυνατότητες

Γιατί: κάθε δυνατότητα που χρησιμοποιεί η εφαρμογή (push, Health, κοινόχρηστος φάκελος με τα widgets, NFC, universal links) πρέπει να είναι ενεργή στο App ID. Αλλιώς η υπογραφή αποτυγχάνει με μήνυμα «Provisioning profile doesn't include the … entitlement».

1. https://developer.apple.com/account/resources/identifiers/list › κουμπί **+**.
2. Διάλεξε **App IDs** › Continue › **App** › Continue.
3. **Description:** `Palee`. **Bundle ID:** **Explicit**, `app.palee.member`.
4. Στο **Capabilities** τσέκαρε:
   - **Associated Domains** (universal links: `palee.app/c/…`, `/join/…`, `/pay/return` κ.λπ.)
   - **Push Notifications**
   - **HealthKit** (μόνο ανάγνωση, ADR-172)
   - **App Groups** (ο κοινός χώρος με τα widgets)
   - **NFC Tag Reading** (εγγραφή ετικέτας check-in)
5. Continue › Register.
6. Πίσω στη λίστα, άνοιξε το `app.palee.member` › **App Groups** › Configure › **+** › `group.app.palee.member` › Continue › Save.
7. Επανάλαβε για το widget: νέο App ID **Explicit** `app.palee.member.widgets` με μόνο **App Groups** (`group.app.palee.member`). Χρειάζεται όταν προστεθεί ο στόχος των widgets στο Xcode (ADR-173).

Πηγή: https://developer.apple.com/help/account/identifiers/register-an-app-id/

### 3.3 Κλειδί push (APNs, αρχείο `.p8`)

Γιατί: με αυτό ο server του Palee στέλνει ειδοποιήσεις στα iPhone. Ένα κλειδί δουλεύει για όλες τις εφαρμογές του λογαριασμού και δεν λήγει.

1. https://developer.apple.com/account/resources/authkeys/list › **+**.
2. **Key Name:** `Palee push`. Τσέκαρε **Apple Push Notifications service (APNs)** › Configure › Environment **Sandbox & Production** › Save › Continue › Register.
3. **Download.** Κατεβαίνει το `AuthKey_<KEYID>.p8`. **Κατεβαίνει μόνο μία φορά.** Βάλ' το αμέσως στον password manager (ως συνημμένο) και σημείωσε το **Key ID** (10 χαρακτήρες).
4. Στα secrets της παραγωγής (ποτέ στο git):

| Μεταβλητή | Τιμή |
|---|---|
| `APNS_TEAM_ID` | το Team ID (§3.1) |
| `APNS_KEY_ID` | το Key ID |
| `APNS_PRIVATE_KEY` | το περιεχόμενο του `.p8` (ή η διαδρομή του αρχείου στον server) |
| `APNS_TOPIC` | `app.palee.member` |

Πηγή: https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns

### 3.4 Η εφαρμογή στο App Store Connect

1. https://appstoreconnect.apple.com › **Apps** › **+** › **New App**.
2. **Platforms:** iOS. **Name:** `Palee`. **Primary Language:** Greek. **Bundle ID:** `app.palee.member` (εμφανίζεται στη λίστα αφού έκανες το §3.2). **SKU:** `palee-member` (εσωτερικός κωδικός, δεν φαίνεται πουθενά). **User Access:** Full Access.
3. Create.

### 3.5 Υπογραφή: αυτόματη, από το Xcode

Το πιο απλό και αυτό που προτείνω: αφήνεις το Xcode να φτιάξει το πιστοποιητικό διανομής (**Apple Distribution**) και τα provisioning profiles.

1. Στο Mac: `cd apps/mobile && npm run bootstrap` (§2).
2. `npx cap open ios`: ανοίγει το project στο Xcode.
3. Xcode › **Settings** › **Accounts** › **+** › Apple Account: συνδέσου με τον λογαριασμό developer.
4. Στο αριστερό πάνελ πάτα **App** (το μπλε εικονίδιο) › στόχος **App** › καρτέλα **Signing & Capabilities**.
5. Τσέκαρε **Automatically manage signing**. **Team:** διάλεξε τη δική σου ομάδα.
6. Έλεγξε ότι κάτω φαίνονται: Associated Domains (`applinks:palee.app`), Push Notifications, HealthKit, App Groups, Near Field Communication Tag Reading. Αν κάποιο έχει κόκκινο σφάλμα, γύρνα στο §3.2.

Τι κάνει το Xcode από πίσω: φτιάχνει ένα ιδιωτικό κλειδί στο **Keychain** του Mac σου, ζητά από την Apple το πιστοποιητικό **Apple Distribution**, και φτιάχνει provisioning profile για το `app.palee.member`. Το ιδιωτικό κλειδί μένει **μόνο σε αυτόν τον Mac**. Για να χτίσεις και από άλλον Mac, δες §8.3.

Για να δεις ποια πιστοποιητικά υπογραφής έχει ο Mac:

```sh
security find-identity -v -p codesigning
```

- `security`: το εργαλείο του macOS για το Keychain.
- `find-identity`: βρίσκει «ταυτότητες», δηλαδή πιστοποιητικό **μαζί με** το ιδιωτικό του κλειδί.
- `-v`: μόνο τις έγκυρες (όχι ληγμένες ή ανακληθείσες). Χωρίς αυτό δείχνει όλες.
- `-p codesigning`: μόνο όσες κάνουν για υπογραφή κώδικα. Χωρίς αυτό δείχνει και άλλες (π.χ. για email).
- **Τι βγάζει:** γραμμές όπως `1) 3F2A…C9 "Apple Distribution: <Όνομα ή Εταιρεία> (A1B2C3D4E5)"` και στο τέλος `1 valid identities found`. Το κείμενο στην παρένθεση είναι το Team ID.

### 3.6 Archive και ανέβασμα (με το Xcode)

1. Πάνω αριστερά, στη λίστα συσκευών, διάλεξε **Any iOS Device (arm64)**.
2. **Product › Archive.** Περιμένεις μερικά λεπτά. Στο τέλος ανοίγει ο **Organizer** με το archive.
3. **Distribute App** › **App Store Connect** › **Upload** › αφήνεις τα default (Upload symbols: ναι, Automatically manage signing: ναι) › **Upload**.
4. Σε 5 έως 30 λεπτά το build εμφανίζεται στο App Store Connect › η εφαρμογή › **TestFlight**. Θα σου ζητήσει την **Export Compliance**: το Palee χρησιμοποιεί μόνο το https του συστήματος, άρα απαντάς ότι χρησιμοποιεί κρυπτογράφηση που εξαιρείται (standard encryption, exempt).

Αν θες το ίδιο από τερματικό (π.χ. αργότερα σε CI):

```sh
cd apps/mobile/ios/App
xcodebuild -project App.xcodeproj -scheme App -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Palee.xcarchive \
  -allowProvisioningUpdates archive
```

- `-project App.xcodeproj`: ποιο project. (Το Palee χρησιμοποιεί Swift Package Manager, άρα δεν υπάρχει `.xcworkspace`.)
- `-scheme App`: το «σχέδιο» χτισίματος του στόχου App.
- `-configuration Release`: χτίσιμο για διανομή. Default είναι ό,τι λέει το scheme για Archive, συνήθως Release.
- `-destination 'generic/platform=iOS'`: για οποιοδήποτε iPhone/iPad, όχι για simulator.
- `-archivePath …`: πού γράφεται το archive. Default: ο φάκελος Archives του Xcode (`~/Library/Developer/Xcode/Archives`).
- `-allowProvisioningUpdates`: επιτρέπει στο Xcode να φτιάξει ή να ανανεώσει provisioning profiles με τον λογαριασμό από το §3.5. Χωρίς αυτό αποτυγχάνει αν λείπει profile.
- `archive`: η ενέργεια. **Τι βγάζει:** στο τέλος `** ARCHIVE SUCCEEDED **` και τον φάκελο `build/Palee.xcarchive`.

Και το ανέβασμα:

```sh
xcodebuild -exportArchive -archivePath build/Palee.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```

- `-exportArchive`: παίρνει το archive και φτιάχνει το πακέτο διανομής.
- `-exportOptionsPlist`: αρχείο με τις επιλογές. Το ελάχιστο για ανέβασμα στο App Store Connect:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>A1B2C3D4E5</string>
</dict>
</plist>
```

  `method` `app-store-connect` σημαίνει «για το App Store και το TestFlight» (default αν λείπει: `development`, που **δεν** ανεβαίνει). `destination` `upload` το στέλνει κατευθείαν στην Apple (default: `export`, που απλώς γράφει ένα `.ipa` στον δίσκο). `teamID` το δικό σου Team ID. Όλες οι επιλογές: `xcodebuild -help`, ενότητα «Available keys for -exportOptionsPlist».
- `-exportPath`: πού γράφει αρχεία και logs.

Πηγές: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases και `man xcodebuild`.

---
