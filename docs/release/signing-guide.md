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

## 4. Android

### 4.1 Πού είναι το `keytool`

Το `keytool` έρχεται με τη Java. Το Android Studio έχει δική του Java μέσα (JBR):

| Σύστημα | Διαδρομή |
|---|---|
| macOS | `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool` |
| Windows | `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe` |
| Linux | `<φάκελος του Android Studio>/jbr/bin/keytool` |

Έλεγχος: τρέξε τη διαδρομή με `-help`. Αν βγάλει λίστα εντολών (`-genkeypair`, `-list` …), είναι εντάξει. Για να μη γράφεις όλη τη διαδρομή κάθε φορά, στο macOS: `export PATH="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin:$PATH"` (ισχύει ως το κλείσιμο του τερματικού).

### 4.2 Φτιάξε το keystore με το κλειδί ανεβάσματος (upload key)

Φτιάξε πρώτα έναν φάκελο **έξω** από το repo, π.χ. `~/palee-signing`, ώστε το αρχείο να μην μπει ποτέ κατά λάθος στο git.

```sh
mkdir -p ~/palee-signing
cd ~/palee-signing
keytool -genkeypair -v \
  -keystore palee-upload.jks \
  -storetype PKCS12 \
  -alias palee-upload \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=Palee, O=<Επωνυμία εταιρείας ή ονοματεπώνυμο>, C=GR"
```

Τι σημαίνει κάθε κομμάτι:

| Επιλογή | Τι κάνει | Default αν τη παραλείψεις | Γιατί αυτή η τιμή |
|---|---|---|---|
| `-genkeypair` | Φτιάχνει νέο ζευγάρι κλειδιών και αυτο-υπογεγραμμένο πιστοποιητικό | (είναι η εντολή) | |
| `-v` | Γράφει περισσότερες λεπτομέρειες για ό,τι κάνει | σιωπηλό | για να δεις τι έγινε |
| `-keystore palee-upload.jks` | Σε ποιο αρχείο μπαίνει το κλειδί (το φτιάχνει αν δεν υπάρχει) | `.keystore` στον φάκελο χρήστη | ένα αρχείο μόνο για το Palee |
| `-storetype PKCS12` | Μορφή του αρχείου | `PKCS12` (Java 9 και νεότερη) | το γράφουμε για σιγουριά: είναι το τυπικό format |
| `-alias palee-upload` | Το όνομα του κλειδιού μέσα στο αρχείο | `mykey` | θα το ξαναγράψεις στο `keystore.properties` |
| `-keyalg RSA` | Αλγόριθμος | στις νεότερες Java δεν υπάρχει default και η εντολή σταματά με σφάλμα· στις παλιές ήταν DSA, που δεν θέλουμε | RSA είναι αυτό που προτείνει η Google |
| `-keysize 2048` | Μέγεθος κλειδιού σε bits | για RSA 2048 ή 3072, ανάλογα με την έκδοση Java | 2048 είναι το ελάχιστο που δέχεται η Google, και αρκεί |
| `-validity 10000` | Πόσες ημέρες ισχύει το πιστοποιητικό | 90 ημέρες | η Google θέλει να ισχύει τουλάχιστον ως τις 22/10/2033· 10000 ημέρες ≈ 27 χρόνια |
| `-dname "…"` | Ποιος είσαι: `CN` όνομα, `O` οργανισμός, `C` χώρα (2 γράμματα) | αν λείπει, σε ρωτά ένα ένα | δεν φαίνεται στους χρήστες· γράψε αληθινά στοιχεία |

Τι θα σε ρωτήσει:

1. `Enter keystore password:` και `Re-enter new password:`. Ο κωδικός του αρχείου. **Φτιάξ' τον με τον password manager** (τουλάχιστον 20 τυχαίοι χαρακτήρες, χωρίς κενά). Δεν φαίνεται όσο γράφεις: είναι φυσιολογικό.
2. Στο `PKCS12` ο κωδικός του κλειδιού είναι **ο ίδιος** με του αρχείου, άρα δεν θα σε ρωτήσει δεύτερο. (Αν δεις `Enter key password for <palee-upload>`, πάτα Enter για να κρατήσει τον ίδιο.)

Τι βγάζει: `Generating 2,048 bit RSA key pair and self-signed certificate (SHA384withRSA) with a validity of 10,000 days for: CN=Palee, …` και `[Storing palee-upload.jks]`. Το αρχείο `palee-upload.jks` είναι πλέον στον φάκελο.

Αν θες να γράψεις τους κωδικούς στην ίδια την εντολή (π.χ. σε script), υπάρχουν `-storepass <κωδικός>` και `-keypass <κωδικός>`. **Μην** το κάνεις στο χέρι: ο κωδικός μένει στο ιστορικό του τερματικού.

Πηγή: https://developer.android.com/studio/publish/app-signing#generate-key και https://docs.oracle.com/en/java/javase/21/docs/specs/man/keytool.html

### 4.3 Δες τι έφτιαξες και πάρε το αποτύπωμα SHA-256

```sh
keytool -list -v -keystore ~/palee-signing/palee-upload.jks -alias palee-upload
```

- `-list`: δείχνει τι έχει το keystore.
- `-v`: με λεπτομέρειες (χωρίς αυτό δείχνει μόνο το alias και ένα αποτύπωμα).
- `-keystore`: ποιο αρχείο. Default: `.keystore` στον φάκελο χρήστη.
- `-alias`: μόνο αυτό το κλειδί. Χωρίς αυτό δείχνει όλα.
- Σε ρωτά τον κωδικό του αρχείου.
- **Τι βγάζει:** `Alias name: palee-upload`, `Valid from: … until: …`, και κάτω από `Certificate fingerprints:` μια γραμμή `SHA256: 3A:9F:…:C2`. Αυτό είναι το **αποτύπωμα του upload key**. Κράτησέ το (δεν είναι μυστικό).

### 4.4 Πες στο Gradle πού είναι το κλειδί

1. Αντίγραψε το `apps/mobile/android/keystore.properties.example` σε `apps/mobile/android/keystore.properties`. Το νέο αρχείο **δεν** μπαίνει στο git (είναι στο `.gitignore`).
2. Συμπλήρωσε:

```properties
storeFile=/Users/<εσύ>/palee-signing/palee-upload.jks
storePassword=<ο κωδικός του αρχείου>
keyAlias=palee-upload
keyPassword=<ο ίδιος κωδικός>
```

- `storeFile`: πλήρης διαδρομή του `.jks` (ή σχετική με το `android/app/`). Στα Windows γράψε `C:/Users/<εσύ>/palee-signing/palee-upload.jks` με κανονικές καθέτους.
- `storePassword` / `keyPassword`: οι κωδικοί. Με `PKCS12` είναι ίδιοι.
- `keyAlias`: το `-alias` του §4.2.

Το `android/app/build.gradle` (ADR-256) διαβάζει αυτό το αρχείο. Αν υπάρχει, κάθε release build υπογράφεται με το upload key. Αν λείπει, το release build βγαίνει ανυπόγραφο και το Play το απορρίπτει.

### 4.5 Χτίσε το AAB

```sh
cd apps/mobile
npm run sync:android
cd android
./gradlew bundleRelease
```

- `npm run sync:android`: γράφει έκδοση, build και links στο project Android και αντιγράφει τα plugins (`configure.mjs` + `cap sync android`).
- `./gradlew`: το Gradle του project (κατεβαίνει μόνο του την πρώτη φορά). Στα Windows: `gradlew.bat bundleRelease`.
- `bundleRelease`: φτιάχνει **AAB** τύπου release, υπογεγραμμένο με το `keystore.properties`. (Το `assembleRelease` φτιάχνει APK, που **δεν** το θέλει το Play.)
- **Τι βγάζει:** `BUILD SUCCESSFUL in …` και το αρχείο `apps/mobile/android/app/build/outputs/bundle/release/app-release.aab`.
- Έλεγχος ότι υπογράφηκε: `keytool -printcert -jarfile app/build/outputs/bundle/release/app-release.aab`. Πρέπει να δείξει `SHA256:` ίδιο με το §4.3.

Εναλλακτικά από το Android Studio: `npx cap open android` › **Build › Generate Signed App Bundle or APK** › **Android App Bundle** › διάλεξε το `.jks`, το alias και τους κωδικούς › **release** › Create.

### 4.6 Firebase (push στο Android)

1. https://console.firebase.google.com › **Add project** › `Palee` (Google Analytics: **όχι**, δεν το χρησιμοποιούμε).
2. Στην αρχική του project › εικονίδιο Android › **Android package name:** `app.palee.member` › Register app.
3. **Download google-services.json** › βάλ' το στο `apps/mobile/android/app/google-services.json`. **Ποτέ στο git** (είναι στο `.gitignore`). Φύλαξε αντίγραφο στον password manager.
4. Project settings (γρανάζι) › **Service accounts** › **Generate new private key** › κατεβαίνει ένα JSON. Αυτό είναι **μυστικό**: μπαίνει στο secret `FCM_SERVICE_ACCOUNT_JSON` της παραγωγής και στον password manager, πουθενά αλλού.

### 4.7 Η εφαρμογή στο Play Console και Play App Signing

1. https://play.google.com/console › **Create app**. App name `Palee`, default language Greek, **App**, **Free**, αποδέχεσαι τις δηλώσεις › Create app.
2. **Test and release › Testing › Internal testing** › Create new release.
3. Στο **App integrity / Play App Signing** επιλέγεις **Use Google-generated key** (προτείνεται: η Google κρατά το app signing key).
4. Ανεβάζεις το `app-release.aab` του §4.5. Το Play κρατά το πιστοποιητικό του upload key από αυτό το πρώτο ανέβασμα: από εδώ και πέρα δέχεται μόνο AAB υπογεγραμμένα με το ίδιο κλειδί.
5. **Release name:** `3.0.0 (1)`, **Release notes** από το `store-listing.md`. Save › Review › Start rollout to Internal testing.
6. **Test and release › Setup › App integrity › App signing**: εδώ βλέπεις **δύο** αποτυπώματα SHA-256: του **App signing key certificate** (της Google) και του **Upload key certificate** (το δικό σου, ίδιο με το §4.3). Αντίγραψε και τα δύο για το §5.

Πηγή: https://support.google.com/googleplay/android-developer/answer/9842756

---

## 5. Τα στοιχεία που πάνε στον server

Ο server του `palee.app` σερβίρει δύο αρχεία που λένε στα κινητά «αυτά τα links ανήκουν στην εφαρμογή Palee»:

- `https://palee.app/.well-known/apple-app-site-association` (iOS)
- `https://palee.app/.well-known/assetlinks.json` (Android)

Τα φτιάχνει μόνος του από αυτές τις μεταβλητές (secrets της παραγωγής, βλ. `.env.example`):

| Μεταβλητή | Τιμή | Από πού |
|---|---|---|
| `APPLE_TEAM_ID` | π.χ. `A1B2C3D4E5` | §3.1 |
| `IOS_BUNDLE_ID` | `app.palee.member` (default, μπορείς να την παραλείψεις) | |
| `ANDROID_PACKAGE_NAME` | `app.palee.member` (default) | |
| `ANDROID_SHA256_CERT_FINGERPRINTS` | τα δύο αποτυπώματα του §4.7 βήμα 6, χωρισμένα με κόμμα | Play Console › App integrity |

Ως ασφάλεια, ο server **αγνοεί** τιμές που δεν έχουν τη σωστή μορφή (Team ID 10 γράμματα/ψηφία, αποτύπωμα 32 ζευγάρια με `:`), όπως τα placeholders του `.env.example`. Τότε απαντά 404 αντί για λάθος αρχείο.

Μετά την αλλαγή των secrets κάνεις restart τον web server (`docker compose up -d web` ή όπως γίνεται το deploy). Δεν χρειάζεται νέο build: οι τιμές διαβάζονται σε κάθε αίτημα.

---

## 6. Έλεγχος ότι τα links ανοίγουν την εφαρμογή

### 6.1 Ο server

```sh
curl -sS https://palee.app/.well-known/apple-app-site-association
curl -sS https://palee.app/.well-known/assetlinks.json
```

- `curl`: κατεβάζει μια σελίδα και τη γράφει στο τερματικό.
- `-s` (silent): χωρίς μπάρα προόδου. `-S` (show-error): αλλά δείξε σφάλματα. Χωρίς αυτά βλέπεις και την πρόοδο.
- **Τι πρέπει να δεις:** στο πρώτο ένα JSON με `"appIDs":["A1B2C3D4E5.app.palee.member"]` και components με `/c/*`, `/join/*`, `/pay/return*`. Στο δεύτερο ένα JSON με `"package_name":"app.palee.member"` και τα δύο αποτυπώματα. Αν δεις `Not found`, οι μεταβλητές του §5 λείπουν ή έχουν λάθος μορφή.
- Έλεγχος της Google: https://developers.google.com/digital-asset-links/tools/generator (Test statement, με `palee.app`, `app.palee.member` και ένα αποτύπωμα).

### 6.2 Android, σε κινητό με την εφαρμογή εγκατεστημένη από το Play (Internal testing)

```sh
adb shell pm get-app-links app.palee.member
```

- `adb`: το εργαλείο του Android SDK για συνδεδεμένα κινητά (USB debugging ανοιχτό). Βρίσκεται στο `<Android SDK>/platform-tools/`.
- `shell pm get-app-links <package>`: δείχνει αν το Android επιβεβαίωσε τα links.
- **Τι πρέπει να δεις:** `palee.app: verified`. Αν δεις `none` ή `1024`, ξανατρέξε τον έλεγχο με `adb shell pm verify-app-links --re-verify app.palee.member`, περίμενε λίγα δευτερόλεπτα και ξαναδές.

### 6.3 iOS

Στο iPhone με την εφαρμογή από το TestFlight, γράψε στις Σημειώσεις `https://palee.app/join/test`, πάτα παρατεταμένα το link: πρέπει να βλέπεις «Άνοιγμα στο Palee». Το iOS κατεβάζει το αρχείο της Apple μέσω του CDN της Apple, οπότε μια αλλαγή μπορεί να θέλει έως 24 ώρες. Στο Mac, `sudo swcutil dl -d palee.app` δείχνει τι βλέπει το CDN (`sudo`: ζητά τον κωδικό του Mac).

Πηγές: https://developer.apple.com/documentation/xcode/supporting-associated-domains και https://developer.android.com/training/app-links/verify-android-applinks

---

## 7. Αριθμοί έκδοσης και build

Δύο αριθμοί, στο `apps/mobile/config/release.json`:

- **`version`** (`3.0.0`): αυτό που βλέπουν οι χρήστες στα stores. Ακολουθεί την έκδοση του Palee. Αλλάζει όταν βγάζεις νέα έκδοση.
- **`build`** (`1`): αυξάνεται **σε κάθε ανέβασμα**, ακόμη κι αν η έκδοση μένει ίδια (π.χ. 3.0.0 build 1, μετά απόρριψη 3.0.0 build 2). Η Apple δεν δέχεται δεύτερο build με ίδιο αριθμό στην ίδια έκδοση. Η Google δεν δέχεται `versionCode` ίσο ή μικρότερο από κάποιο που ανέβηκε ποτέ.

Πώς τον αλλάζεις:

- Μόνιμα: άλλαξε το `build` στο `release.json`, commit, και τρέξε `npm run configure` (γράφει στο `build.gradle` και στο Xcode project).
- Για ένα μόνο build: `PALEE_BUILD_NUMBER=2 npm run sync`.

Το `configure` σταματά με σφάλμα αν η έκδοση δεν είναι της μορφής `X.Y.Z` ή αν το build δεν είναι ακέραιος από 1 έως 2 100 000 000 (όριο της Google).

---

## 8. Ασφαλής φύλαξη

### 8.1 Τι κρατάς και πού

| Τι | Μυστικό; | Πού |
|---|---|---|
| `palee-upload.jks` και ο κωδικός του | **Ναι** | password manager (αρχείο + κωδικός) **και** ένα δεύτερο αντίγραφο εκτός σπιτιού (π.χ. κρυπτογραφημένο USB σε άλλο μέρος) |
| `AuthKey_<KEYID>.p8` (APNs) | **Ναι** | password manager και secrets παραγωγής |
| JSON του Firebase service account | **Ναι** | password manager και secrets παραγωγής |
| `google-services.json` | Όχι πολύ (περιέχει δημόσια ids), αλλά δεν μπαίνει στο git | password manager |
| Κωδικοί λογαριασμών Apple και Google | **Ναι**, με έλεγχο δύο βημάτων | password manager |
| Team ID, Key ID, αποτυπώματα SHA-256 | Όχι | password manager για ευκολία |
| Κωδικοί λογαριασμών review (`review-member@…`) | Ναι | password manager· αλλάζουν μετά από κάθε έγκριση |

Κανόνες:
- **Ποτέ** σε git, email, chat, Google Drive χωρίς κρυπτογράφηση, ή screenshot.
- Το repo έχει ήδη στο `.gitignore`: `*.jks`, `*.keystore`, `*.p8`, `*.p12`, `android/keystore.properties`, `google-services.json`. Πριν από κάθε commit, `git status`: αν δεις κάποιο από αυτά, σταμάτα.

### 8.2 Αν χαθεί ή διαρρεύσει

- **Upload key (Android):** Play Console › App integrity › App signing › **Request upload key reset**. Φτιάχνεις νέο με το §4.2, εξάγεις το πιστοποιητικό με `keytool -export -rfc -keystore palee-upload.jks -alias palee-upload -file upload_certificate.pem` (`-export`: εξάγει μόνο το δημόσιο πιστοποιητικό· `-rfc`: σε μορφή κειμένου PEM, default είναι δυαδική· `-file`: πού το γράφει, default η οθόνη) και το ανεβάζεις. Η Google το ενεργοποιεί σε λίγες ημέρες. Μετά ενημερώνεις το `ANDROID_SHA256_CERT_FINGERPRINTS`.
- **Κλειδί APNs:** στη σελίδα Keys το κάνεις **Revoke**, φτιάχνεις νέο (§3.3) και αλλάζεις τα secrets.
- **Πιστοποιητικό Apple Distribution:** Certificates › Revoke, και το Xcode φτιάχνει νέο μόνο του. Οι εφαρμογές που έχουν ήδη κατέβει **δεν** επηρεάζονται.
- **Κωδικός λογαριασμού:** αλλάζεις αμέσως και ελέγχεις τα μέλη της ομάδας (Users and Access).

### 8.3 Χτίσιμο iOS από δεύτερο Mac

Είτε συνδέεσαι με τον ίδιο λογαριασμό στο Xcode και αφήνεις να φτιάξει δεύτερο πιστοποιητικό (επιτρέπονται λίγα ταυτόχρονα), είτε εξάγεις το υπάρχον: **Keychain Access** › My Certificates › δεξί κλικ στο «Apple Distribution: …» › Export › `.p12` με κωδικό, και το εισάγεις στον άλλον Mac. Το `.p12` περιέχει το ιδιωτικό κλειδί: φυλάγεται όπως το `.jks`.

---

## 9. Πού ψάχνεις όταν κάτι δεν πάει καλά

| Πρόβλημα | Πού κοιτάς |
|---|---|
| «No signing certificate» ή «Provisioning profile doesn't include …» στο Xcode | §3.2 (δυνατότητες στο App ID) και §3.5 (Team). https://developer.apple.com/help/account/ |
| Το build δεν εμφανίζεται στο App Store Connect | Email από την Apple με το πρόβλημα (συχνά: build number ξανά, ή λείπει κείμενο άδειας). App Store Connect › TestFlight › Build Activity |
| «You uploaded an APK or Android App Bundle that was signed in debug mode» | Λείπει το `keystore.properties` (§4.4) |
| «Version code 1 has already been used» | §7: ανέβασε τον αριθμό build |
| «Your Android App Bundle is signed with the wrong key» | Υπέγραψες με άλλο κλειδί από το upload key (§4.3, σύγκρινε το SHA-256) |
| Τα links ανοίγουν τον browser αντί για την εφαρμογή | §6 |
| Δεν έρχονται push | iOS: §3.3 και `PALEE_APS_ENVIRONMENT=production` για TestFlight/App Store. Android: §4.6 |
| Εντολή που δεν καταλαβαίνεις | `keytool -<εντολή> -help` (π.χ. `keytool -genkeypair -help`), `xcodebuild -help`, `man security`, `./gradlew help --task bundleRelease` |

Επίσημη τεκμηρίωση:
- Apple, Distribution: https://developer.apple.com/documentation/xcode/distribution
- Apple, App Store Connect help: https://developer.apple.com/help/app-store-connect/
- Android, Sign your app: https://developer.android.com/studio/publish/app-signing
- Google Play Console help: https://support.google.com/googleplay/android-developer/
- Capacitor, deploying: https://capacitorjs.com/docs/ios/deploying-to-app-store και https://capacitorjs.com/docs/android/deploying-to-google-play
