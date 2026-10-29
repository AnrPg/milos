# Palee v3.0.0: έτοιμο για τα πρώτα pilot boxes

> Ημερομηνία: 29 Οκτωβρίου 2026 · Ζήτησε: ANR · Branch ενσωμάτωσης: `claude/project-thread-wwetd7` (worktree `palee-v3`)
> Πηγές απαιτήσεων: `docs/plans/competitive-parity-and-beyond.md` (Φάση 1) και `docs/plans/government-fiscal-integrations.md` (αγορές MVP).
> Αρχές: §4 του vision doc, hexagonal (ADR-043), κάθε αλλαγή με tests (UI, web, e2e), ονόματα από το `docs/product/ontology.md`.

## 1. Τι περιλαμβάνει και πώς το διάβασα

ANR (29/10, 10:47 Ελλάδα): «begin these and then the rest of phase 0».

- **«These»** = η σειρά διασυνδέσεων για τις αγορές του MVP: Ελλάδα (myDATA) → φόροι, πρότυπα παραστατικών, exports λογιστικής → απαραβίαστο ημερολόγιο (NF525) → Peppol → TSE/RKSV.
- **«Phase 0»** = όλα τα **P0** του `competitive-parity-and-beyond.md` (ANR, 29/10). Είναι τα ίδια με τη Φάση 1 «Έτοιμο για pilots» του backlog: CP-A1 online πληρωμές, CP-A2 Tap to Pay, CP-A3 πληρωμή στην κράτηση, CP-A4 σελίδα αγοράς, CP-B1 έγγραφα με υπογραφή, CP-D1 οθόνη box, CP-F1 stores, CP-F3 εισαγωγή CSV, CP-G1 τιμές, CP-H1 απλοποίηση ρυθμίσεων, CP-H2 συνταγές στησίματος. Τα CP-H4 (δοκιμή με ιδιοκτήτες) και CP-G6 (pilots) δεν είναι κώδικας: το V3-M14 ετοιμάζει το υλικό τους.
- **Έκδοση: v3.0.0.** Αλλάζει η ροή του χρήματος (πραγματικές χρεώσεις, νόμιμα παραστατικά) και το API των οικονομικών. Είναι η πρώτη έκδοση που μπορεί να χρησιμοποιήσει ένα πραγματικό box στην Ελλάδα. Μία major έκδοση το λέει καθαρά, και αφήνει τα v2.x για διορθώσεις της τρέχουσας παραγωγής.

## 2. Έρευνα: τι επιβάλλει ο νόμος και τι επιβάλλουν οι πάροχοι

| Θέμα | Τι ισχύει | Τι σημαίνει για το σχέδιο | Πηγές |
|---|---|---|---|
| myDATA | Κάθε παραστατικό διαβιβάζεται. Από 2026 το B2B εκδίδεται μόνο μέσω πιστοποιημένου παρόχου ή των εργαλείων της ΑΑΔΕ. Από 1/2/2027, κατά μία πηγή, τελειώνει η αποστολή από ERP. Η ΑΑΔΕ δημοσιεύει ξεχωριστό API για ERP και για παρόχους (v2.0.x, 2026) | Το Palee δεν γίνεται πάροχος. Εκδίδει **μέσω παρόχου** (adapter ανά πάροχο). Το ERP channel μένει μόνο για δοκιμές με το mydata-dev | [ΑΑΔΕ API παρόχων v2.0.2](https://www.aade.gr/sites/default/files/2026-09/myDATA%20API%20Documentation_Providers_v2%200%202_official_0.pdf) · [ΑΑΔΕ API ERP v1.0.9](https://aade.gr/sites/default/files/2024-10/ENG_myDATA%20API%20Documentation%20v1.0.9_official_erp.pdf) · [KPMG](https://kpmg.com/us/en/taxnewsflash/news/2025/09/greece-compliance-deadlines-electronic-invoicing.html) · [Taxually](https://www.taxually.com/blog/greece-b2b-e-invoicing-2026) |
| Διασύνδεση POS | Η κάρτα πρέπει να είναι δεμένη με την απόδειξη (ΦΗΜ ή πάροχος). Πρόστιμο 10.000 € (ΔΕΔ 1441/2026) | Κάθε χρέωση κάρτας στο Palee παράγει παραστατικό στην ίδια συναλλαγή, με τα στοιχεία της πληρωμής | [ΔΕΔ 1441/2026](https://www.taxheaven.gr/circulars/54727/ded-1441-2026) · [ΑΑΔΕ απόφαση 12/2022](https://www.aade.gr/sites/default/files/2022-12/dt_30.12.2022._0.pdf) |
| NF525 (FR) | Απαραβίαστα δεδομένα, διορθώσεις μόνο με αντίθετες εγγραφές, ασφάλεια, διατήρηση, αρχειοθέτηση, πρόσβαση της φορολογικής αρχής. Πιστοποιητικό ή βεβαίωση εκδότη (επανήλθε με τον ν. 2026-103) | Ενιαίο απαραβίαστο ημερολόγιο (αλυσίδα hash, κλεισίματα περιόδων, εξαγωγή αρχείου) για όλες τις χώρες. Η βεβαίωση εκδότη θα υπογραφεί από τον ANR | [BOFiP BOI-TVA-DECLA-30-10-30](https://bofip.impots.gouv.fr/bofip/10691-PGP.html) · [Kohen Avocats](https://kohenavocats.fr/?p=1995962) |
| Πληρωμές, PSD2/SCA | Η πρώτη χρέωση μιας σειράς θέλει SCA. Οι επόμενες ίδιες χρεώσεις είναι merchant-initiated χωρίς SCA. Αλλαγή ποσού ή κάρτας θέλει νέο SCA | Πρώτη πληρωμή στην hosted σελίδα του παρόχου με συναίνεση για επόμενες. Οι ανανεώσεις είναι MIT. Αλλαγή τιμής → νέα συναίνεση | [EBA Q&A](https://www.eba.europa.eu/node/7263) · [GoCardless](https://gocardless.com/guides/strong-customer-authentication/sca-exemptions) |
| PCI DSS | Ο έμπορος με **redirect** σε σελίδα πληρωμής του παρόχου είναι εκτός των νέων κριτηρίων script του SAQ A. Το iframe θέλει επιπλέον ελέγχους | Μόνο redirect (Viva Smart Checkout, Stripe Checkout). Κανένα στοιχείο κάρτας δεν περνά από το Palee | [PCI SSC FAQ](https://blog.pcisecuritystandards.org/faq-clarifies-new-saq-a-eligibility-criteria-for-e-commerce-merchants) · [TrustedSec](https://trustedsec.com/blog/the-hidden-trap-in-the-pci-dss-saq-a-changes) |
| Viva | OAuth2, `POST /checkout/v2/orders` με `allowRecurring`, επόμενες χρεώσεις με αναφορά στην αρχική συναλλαγή, webhooks (π.χ. 1796 Transaction Payment Created) με κλειδί επαλήθευσης και 24 επαναλήψεις, έλεγχος με Retrieve Transaction. Demo περιβάλλον | Adapter Viva με webhook που **δεν εμπιστεύεται** το σώμα: ξαναδιαβάζει τη συναλλαγή από το API πριν την καταχωρίσει | [Viva recurring](https://developer.viva.com/tutorials/payments/create-a-recurring-payment/) · [Viva webhooks](https://developer.viva.com/webhooks-for-payments) · [Smart Checkout guide](https://euhelp.viva.com/en/articles/10305230-smart-checkout-integration-guide) |
| Tap to Pay | Η εφαρμογή «Viva.com Terminal» δέχεται αίτημα πληρωμής από άλλη εφαρμογή (Android intent, iOS URL scheme) και επιστρέφει αποτέλεσμα. Tap to Pay on iPhone σε πολλές χώρες της Ευρώπης | Capacitor plugin app-to-app. Το Palee δεν αγγίζει την κάρτα | [Viva POS APIs](https://developer.viva.com/apis-for-point-of-sale/) · [SoftPOS apps](https://developer.viva.com/apis-for-point-of-sale/card-terminal-apps/) |
| Stores | Apple 3.1.3(e): φυσικές υπηρεσίες πληρώνονται εκτός IAP. Google Play: οι συνδρομές γυμναστηρίου **δεν** επιτρέπεται να χρεώνονται με Play Billing. Οι ψηφιακές συνδρομές fitness θέλουν Play Billing | Πληρωμές box (συνδρομές, PT, shop) μέσω Viva/Stripe. Ψηφιακές συνδρομές πλατφόρμας προς μέλη δεν πωλούνται στην εφαρμογή | [Google Play Payments](https://support.google.com/googleplay/android-developer/answer/9858738) · [Apple forums 3.1.3(e)](https://developer.apple.com/forums/thread/747239) |
| Έγγραφα, υπογραφές | eIDAS άρθρο 25: η απλή ηλεκτρονική υπογραφή έχει έννομο αποτέλεσμα. Η αποδεικτική της αξία εξαρτάται από το audit trail | Απλή υπογραφή με ισχυρό ίχνος: hash κειμένου και έκδοσης, χρόνος, IP, συσκευή, ταυτότητα λογαριασμού, PDF πιστοποιητικό | [eIDAS (Adobe/axiocap σύνοψη)](https://www.axiocap.com/en/legal-summary/legal-regime-electronic-signatures) · [ValidSign](https://validsign.eu/resources/legislation) |
| Βεβαίωση υγείας (GR) | Προϋπόθεση εγγραφής και ανανέωσης σε ιδιωτικό γυμναστήριο: βεβαίωση παθολόγου ή καρδιολόγου (παιδιάτρου έως 16), ισχύει 1 έτος | Τύπος εγγράφου «Βεβαίωση υγείας» με λήξη, υπενθύμιση, προαιρετικό μπλοκάρισμα κράτησης. Ειδική κατηγορία δεδομένων (GDPR άρθρο 9): ελάχιστα δεδομένα, μόνο ημερομηνίες και αρχείο, πρόσβαση μόνο σε staff με δικαίωμα | [opengov, άρθρο 72](https://www.opengov.gr/cultureathl/?p=6928) · [Κανονισμός γυμναστηρίου Καλλιθέας](https://kallithea.gr/wp-content/uploads/2024/10/ΕΣΩΤΕΡΙΚΟΣ-ΚΑΝΟΝΙΣΜΟΣ-ΓΥΜΝΑΣΤΗΡΙΟΥ2.pdf) |
| Δικαίωμα υπαναχώρησης | Σύμβαση από απόσταση: 14 ημέρες. Αν λείπει η ενημέρωση, παρατείνεται έως 12 μήνες | Online αγορά: εμφάνιση του δικαιώματος, επιλογή «έναρξη πριν τις 14 ημέρες» με αναλογική χρέωση, καταγραφή | [Οδηγία 2011/83/ΕΕ άρθρο 9](https://www.legislation.gov.uk/eudr/2011/83/article/9) · [άρθρο 10](https://www.legislation.gov.uk/eudr/2011/83/article/10/data.htm) |
| TSE (DE) | fiskaly SIGN DE: TSS με Admin PIN, transaction start/finish, χρόνοι από το cloud, TEST/LIVE | Adapter για είσπραξη στο ταμείο σε Γερμανία | [fiskaly quickstart](https://workspace.fiskaly.com/countries/germany/quickstart/) · [SIGN DE spec](https://workspace.fiskaly.com/specs/sign-de-v2.json) |
| Peppol | Access point as a service (π.χ. Storecove): legal entity, Peppol ID, `invoice_submissions`, εφεδρεία email | Παραγωγή UBL (EN 16931) από το Palee, αποστολή μέσω port με adapter παρόχου | [Storecove](https://storecove.com/blog/en/access-point-as-a-service-sending) · [efacture.belgium.be](https://efacture.belgium.be/en/partner/storecove) |
| QR-bill (CH/LI) | Από 21/11/2025 μόνο δομημένες διευθύνσεις· v2.4 ισχύει από 14/11/2026 | Γεννήτρια QR-bill κατά v2.4 | [SIX IG v2.4](https://www.six-group.com/dam/download/banking-services/standardization/qr-bill/ig-qr-bill-v2.4-en.pdf) |
| Φόρος ΗΠΑ | Ανά πολιτεία και πόλη· Stripe Tax ή Avalara υπολογίζουν | Port `SalesTaxCalculator` με adapter χειροκίνητου συντελεστή τώρα, Stripe Tax μετά | [Stripe Tax](https://docs.stripe.com/tax/how-tax-works) · [TaxJar](https://blog.taxjar.com/06-21-sales-tax-fitness-memberships/) |

**Όρια της έρευνας:** οι πηγές είναι κυρίως σύνοψη από εταιρείες συμμόρφωσης. Πριν από το πρώτο box κάθε χώρας χρειάζεται επιβεβαίωση από φοροτεχνικό και νομικό. Το κείμενο των εγγράφων (όροι, ενημέρωση GDPR) είναι **πρόχειρο για νομικό έλεγχο**, όχι τελικό.

## 3. Αρχιτεκτονική

### 3.1 Νέα και αλλαγμένα bounded contexts

- **`Palee.Fiscal` (νέο):** νομική ταυτότητα επιχείρησης (επωνυμία, χώρα, ΑΦΜ/VAT, ΔΟΥ, διεύθυνση), προφίλ χώρας, φορολογικά παραστατικά, απαραβίαστο ημερολόγιο, κλεισίματα περιόδων, αποστολή στην αρχή, συντελεστές φόρου.
- **`Palee.Payments` (νέο):** online πληρωμές για όλες τις ροές (συνδρομές, πακέτα, κράτηση, shop): checkout sessions, αποθηκευμένα μέσα (μόνο tokens του παρόχου), επαναλαμβανόμενες χρεώσεις, webhooks, επιστροφές, πληρωμές στο ταμείο (Tap to Pay). Το `Shop.Ports.PaymentProvider` (ADR-190) μεταφέρεται εδώ ως γενικό port.
- **`Palee.Documents` (νέο):** πρότυπα εγγράφων με εκδόσεις, αιτήματα υπογραφής, υπογραφές με ίχνος, βεβαιώσεις υγείας με λήξη.
- **`Palee.Imports` (νέο):** εισαγωγή CSV με αντιστοιχίσεις, δοκιμαστική εκτέλεση, idempotent εφαρμογή.
- **Finance (αλλάζει):** η καταχώριση πληρωμής ζητά από το Fiscal το νόμιμο παραστατικό. Το Fiscal δεν ξέρει τίποτα για πακέτα. Παίρνει «γραμμές πώλησης» με κατηγορία φόρου.

### 3.2 Ports (domain/application) και adapters (infrastructure)

| Port | Adapters σε αυτή την έκδοση | Αργότερα |
|---|---|---|
| `Fiscal.Ports.AuthorityGateway` (έκδοση/διαβίβαση/ακύρωση) | `Sandbox` (dev/test/demo), `MyDataErp` (ΑΑΔΕ mydata-dev, μόνο δοκιμές), `MyDataProvider` (γενικός, ενεργοποιείται όταν επιλεγεί πάροχος) | Ιταλία, Πορτογαλία, Ισπανία |
| `Fiscal.Ports.CashRegisterSecurity` (TSE/RKSV) | `Sandbox`, `FiskalySignDe`, `FiskalySignAt` | — |
| `Fiscal.Ports.EInvoiceNetwork` (Peppol) | `Sandbox`, `Storecove` | Άλλα access points |
| `Fiscal.Ports.SalesTaxCalculator` | `RateTable` (ΕΕ, CH, UK, χειροκίνητοι συντελεστές ΗΠΑ) | `StripeTax`, `Avalara` |
| `Fiscal.Ports.AccountingExportFormat` | `Datev`, `XeroCsv`, `QuickBooksCsv`, `SageCsv`, `Bexio`, `GenericCsv` | API συνδέσεις |
| `Payments.Ports.Gateway` | `Sandbox`, `Viva`, `Stripe` | — |
| `Payments.Ports.TerminalLauncher` (web/native) | Capacitor plugin Viva Terminal (Android intent, iOS URL scheme), `Sandbox` | Viva Cloud Terminal |
| `Documents.Ports.SignatureEvidenceStore` | αποθήκευση PDF μέσω του υπάρχοντος Storage port | Πάροχος προηγμένης υπογραφής |

Κάθε adapter επιλέγεται στο composition root (config), ποτέ στο domain. Κάθε εξωτερική κλήση περνά από outbox με επαναλήψεις και idempotency key. Κανένα μυστικό σε κώδικα: διαπιστευτήρια ανά box σε κρυπτογραφημένη στήλη (Cloak/AES-GCM με κλειδί από env), διαπιστευτήρια πλατφόρμας σε env.

### 3.3 Βασικοί κανόνες ακεραιότητας

1. **Χρήματα:** ακέραια cents και νόμισμα ISO 4217 παντού. Υποστηρίζονται EUR, GBP, USD, CHF.
2. **Ένα παραστατικό δεν αλλάζει ποτέ.** Διόρθωση = πιστωτικό ή ακυρωτικό που αναφέρει το αρχικό. Η αρίθμηση είναι συνεχής ανά σειρά και ανά box, χωρίς κενά (με κλείδωμα γραμμής μετρητή).
3. **Απαραβίαστο ημερολόγιο:** κάθε γεγονός (έκδοση, πληρωμή, ακύρωση, κλείσιμο) γράφεται με `hash = SHA-256(προηγούμενο hash + κανονικοποιημένο JSON)`. Ημερήσια, μηνιαία και ετήσια κλεισίματα με σύνολα. Επαλήθευση αλυσίδας με εργασία και endpoint. Ο ρόλος της βάσης δεν έχει UPDATE/DELETE στους πίνακες του ημερολογίου (RLS και GRANT).
4. **Πληρωμή → παραστατικό στην ίδια λογική συναλλαγή.** Αν η αρχή δεν απαντά, το παραστατικό μένει «προς διαβίβαση» και το outbox ξαναδοκιμάζει. Το μέλος βλέπει την απόδειξη με την ένδειξη «εκκρεμεί διαβίβαση». Δεν χάνεται ποτέ ούτε η πληρωμή ούτε το παραστατικό.
5. **Webhooks:** επαλήθευση προέλευσης και επανάκτηση της συναλλαγής από τον πάροχο. Idempotent ανά αναγνωριστικό γεγονότος.
6. **Ποτέ στοιχεία κάρτας** στο Palee. Μόνο tokens και τελευταία 4 ψηφία, όπως τα επιστρέφει ο πάροχος.
7. **Ρυθμίσεις χώρας:** το προφίλ χώρας (GR, CY, DE, AT, CH, LI, LU, FR, BE, MC, GB, US) ορίζει: τι παραστατικά υπάρχουν, ποια αρχή, ποιο ημερολόγιο, ποιοι συντελεστές, ποιες υποχρεωτικές αναγραφές, ποια exports. Νέα χώρα = νέο προφίλ και adapters, όχι αλλαγή στο domain.

## 4. Ορόσημα

Κάθε ορόσημο: ADR, migration, domain + ports + application + adapters + controllers/OpenAPI + web + i18n (12 γλώσσες) + tests (API, vitest, Playwright). Ένα commit (ή λίγα) ανά ορόσημο στο branch της v3 και ένα draft PR προς `main` που μεγαλώνει (το cloud περιβάλλον επιτρέπει push μόνο σε ένα branch). Αριθμοί ADR από **ADR-240**, migrations από **20270201000000**, για να μην συγκρουστούν με άλλα threads.

| # | Ορόσημο | ADR | Περιεχόμενο |
|---|---|---|---|
| V3-M1 | Νομική ταυτότητα, προφίλ χώρας, φορολογικά παραστατικά, απαραβίαστο ημερολόγιο | 240–242 | `Palee.Fiscal`, κλεισίματα περιόδων, επαλήθευση αλυσίδας, εξαγωγή αρχείου ελέγχου |
| V3-M2 | myDATA | 243 | Port αρχής, Sandbox, ERP (mydata-dev), γενικός adapter παρόχου, αντιστοίχιση τύπων παραστατικών (π.χ. 11.2 ΑΠΥ, 2.1 ΤΠΥ, 5.1 πιστωτικό), outbox, οθόνη κατάστασης |
| V3-M3 | Φόροι, πρότυπα παραστατικών, QR-bill, exports λογιστικής | 244–245 | Πίνακας συντελεστών, κατηγορίες φόρου σε πακέτα/προϊόντα, PDF ανά χώρα και γλώσσα, DATEV/Xero/QuickBooks/Sage/bexio |
| V3-M4 | Online πληρωμές | 246–247 | `Palee.Payments`, Viva και Stripe, αποθηκευμένη κάρτα, αυτόματες ανανεώσεις, επαναπροσπάθειες, webhooks, επιστροφές, σύνδεση με τα παραστατικά |
| V3-M5 | Πληρωμή στην κράτηση, σελίδα αγοράς, online πληρωμή στο shop | 248 | Αγορά μίας θέσης ή πακέτου στο ίδιο βήμα, δημόσια σελίδα πακέτων, υπαναχώρηση 14 ημερών |
| V3-M6 | Tap to Pay | 249 | Capacitor plugin Viva Terminal, ροή staff, παραστατικό |
| V3-M7 | Peppol, TSE, RKSV | 250–251 | UBL EN 16931 (Peppol BIS 3.0, XRechnung), Storecove, fiskaly SIGN DE/AT |
| V3-M8 | Έγγραφα και υπογραφές | 252 | Πρότυπα με εκδόσεις, απλή υπογραφή με ίχνος, μαζική αποστολή, βεβαίωση υγείας, φραγή κράτησης |
| V3-M9 | Οθόνη box | 253 | WOD, κρατήσεις, live leaderboard, σύνδεση με κωδικό |
| V3-M10 | Εισαγωγή CSV | 254 | Οδηγός, αντιστοιχίσεις Wodify/PushPress/Zen Planner/Arbox/Excel, δοκιμαστική εκτέλεση |
| V3-M11 | Συνταγές στησίματος και απλοποίηση ρυθμίσεων | 255 | Συνταγές ανά τύπο box, «Προχωρημένα», έλεγχος διακοπτών |
| V3-M12 | Stores | 256 | Bundle id, πολιτικές πληρωμών, κείμενα καταχωρίσεων, οδηγός υπογραφής για τον ANR |
| V3-M13 | Έκδοση | — | Πλήρες gate, e2e, release notes, οδηγίες tag v3.0.0 |
| V3-M14 | Pilots και δοκιμή ευχρηστίας (CP-G6, CP-H4) | — | Πρόγραμμα pilot, σενάριο δοκιμής με ιδιοκτήτες, ερωτηματολόγιο, πώς συλλέγουμε κριτικές |

## 5. Αποφάσεις (με την προτεινόμενη επιλογή, που υλοποιείται μέχρι να πει άλλο ο ANR)

1. **Πάροχος πληρωμών:** Viva για Ευρώπη και ΗΒ, Stripe για ΗΠΑ (και ως εναλλακτική παντού). Και οι δύο χτίζονται πίσω από το ίδιο port.
2. **Πάροχος myDATA:** ανοιχτό. Χτίζεται γενικός adapter παρόχου + Sandbox + ERP για δοκιμές. Ο συγκεκριμένος πάροχος συνδέεται όταν ο ANR υπογράψει.
3. **Υπογραφή:** απλή ηλεκτρονική υπογραφή με ισχυρό ίχνος. Port έτοιμο για προηγμένη αργότερα.
4. **Τιμές πλατφόρμας (CP-G1):** μένει απόφαση του ANR. Ο κώδικας δεν εξαρτάται από αυτή.
5. **Ποιος πληρώνει την προμήθεια της κάρτας:** το box (προεπιλογή). Η χρέωση στο μέλος (surcharge) δεν χτίζεται, γιατί στην ΕΕ απαγορεύεται για καταναλωτικές κάρτες (PSD2 άρθρο 62(4), χωρίς πηγή σε αυτή την έρευνα, θέλει επιβεβαίωση).

## 6. Πρόοδος

| Ορόσημο | Κατάσταση | PR |
|---|---|---|
| Σχέδιο | Γράφτηκε | — |
| V3-M1 | Backend έτοιμο (ADR-240–242, 9 endpoints, 53 tests). Οθόνες μετά τα mockups | draft PR |
