# Κρατικές διασυνδέσεις τύπου myDATA ανά χώρα

> Ημερομηνία: 29 Οκτωβρίου 2026 · Ζήτησε: ANR · Συνδέεται με το CP-A7 στο `docs/plans/competitive-parity-and-beyond.md`
>
> **Τι καλύπτει:** τις χώρες των 12 γλωσσών του Palee (el, en, de, fr, es, it, pt-PT, nl, bg, ru, ar, he) και τις αγγλόφωνες χώρες. Για κάθε χώρα: ποιο κρατικό σύστημα αντιστοιχεί στο myDATA, αν αφορά ένα box (που πουλά κυρίως σε ιδιώτες, B2C), και τι θα έπρεπε να χτίσει το Palee. Όπου δεν υπάρχει κρατικό σύστημα ή όπου στην πράξη κυριαρχεί ιδιωτικό λογισμικό, το γράφει.
>
> **Προσοχή:** οι πηγές είναι κυρίως εταιρείες συμμόρφωσης (KPMG, Sovos, Comarch, vatcalc κ.ά.) και λιγότερο οι ίδιες οι φορολογικές αρχές. Οι ημερομηνίες αλλάζουν συχνά και πολλές πηγές διαφωνούν μεταξύ τους. Οι διαφωνίες σημειώνονται. **Πριν από κάθε υλοποίηση χρειάζεται επιβεβαίωση από την επίσημη αρχή και από φοροτεχνικό της χώρας.** Όσα σημεία δεν έχουν πηγή σημειώνονται «χωρίς πηγή».

## Η σύντομη εικόνα

Τα συστήματα χωρίζονται σε τέσσερις ομάδες:

1. **Αναφορά ή έγκριση κάθε παραστατικού από το κράτος, και για ιδιώτες (B2C):** Ελλάδα (myDATA), Ιταλία (SdI και corrispettivi), Πορτογαλία (πιστοποιημένο λογισμικό, ATCUD, SAF-T), Ισπανία (VeriFactu, από το 2027), Σαουδική Αραβία (FATOORA), Αίγυπτος (e-receipt), Ρωσία (54-ФЗ online ταμεία). **Εδώ ένα box δεν μπορεί να λειτουργήσει νόμιμα χωρίς διασύνδεση.**
2. **Πιστοποιημένο ταμείο ή λογισμικό ταμείου, χωρίς αναφορά κάθε απόδειξης:** Γερμανία (KassenSichV/TSE), Αυστρία (RKSV), Γαλλία (NF525), Βουλγαρία (φορολογικές συσκευές, SUPTO).
3. **Υποχρεωτικό ηλεκτρονικό τιμολόγιο μόνο μεταξύ επιχειρήσεων (B2B), τώρα ή σύντομα:** Βέλγιο (από 2026), Γαλλία (από 9/2026), Γερμανία (2027–28), Ισραήλ (αριθμός κατανομής), ΗΑΕ (2027), Ιορδανία, Ιρλανδία (2028), ΗΒ (2029), Ολλανδία (2030), Βουλγαρία (σχέδιο 2028). Για ένα box αυτό αφορά λίγα παραστατικά: εταιρικές συνδρομές, χορηγίες, perks συνεργατών.
4. **Κανένα κρατικό σύστημα· κυριαρχεί ιδιωτικό λογιστικό λογισμικό:** ΗΠΑ, Καναδάς, Αυστραλία, Νέα Ζηλανδία, Κύπρος, Ελβετία, και στην πράξη ΗΒ και Ιρλανδία μέχρι το 2028–29. Εκεί η σωστή «διασύνδεση» είναι με το λογιστικό λογισμικό (QuickBooks, Xero, Sage, DATEV κ.λπ.) και όχι με το κράτος.

## Πίνακας

| Χώρα | Γλώσσα Palee | Σύστημα | Αφορά το B2C ενός box; | Τι χτίζει το Palee | Προτεραιότητα |
|---|---|---|---|---|---|
| Ελλάδα | el | myDATA (ΑΑΔΕ), πάροχοι ηλεκτρονικής τιμολόγησης, διασύνδεση POS–ΦΗΜ | **Ναι** | Διασύνδεση με πιστοποιημένο πάροχο | **P0** |
| Κύπρος | el | Κανένα για B2B/B2C (μόνο B2G) | Όχι | Τίποτα κρατικό· export για λογιστή | P2 |
| Βουλγαρία | bg | Φορολογικές συσκευές και SUPTO (Ν-18)· σχέδιο e-invoicing 2028 | Ναι, για μετρητά/κάρτες στο ταμείο | Συνεργασία με πιστοποιημένο SUPTO | P2 |
| Γερμανία | de | KassenSichV/TSE, δήλωση στο ELSTER· XRechnung/ZUGFeRD B2B 2027–28· DATEV | Ναι, αν υπάρχει ταμείο | Cloud TSE + export DATEV + XRechnung | P1 |
| Αυστρία | de | RKSV (Registrierkasse με υπογραφή), FinanzOnline | Ναι | Cloud υπογραφή RKSV | P2 |
| Ελβετία | de, fr, it | Κανένα· QR-bill για πληρωμές | Όχι | QR-bill στα τιμολόγια, export bexio | P2 |
| Γαλλία | fr | NF525 για λογισμικό ταμείου· e-invoicing μέσω PA από 9/2026· e-reporting B2C | **Ναι** (NF525, e-reporting) | Πιστοποίηση/attestation NF525 + PA | P1 |
| Βέλγιο | fr, nl | Peppol B2B από 1/2026· e-reporting 2028 | Όχι (B2C εκτός) | Αποστολή B2B μέσω Peppol | P2 |
| Ολλανδία | nl | Κανένα σήμερα· B2B από 7/2030 | Όχι | Export για λογιστικό λογισμικό | P2 |
| Ιταλία | it | SdI (FatturaPA) για όλα τα τιμολόγια· corrispettivi telematici· σύνδεση POS–RT | **Ναι** | Μέσω πιστοποιημένου intermediario | P1 |
| Ισπανία | es | VeriFactu από 1/2027 (εταιρείες) και 7/2027 (λοιποί)· TicketBAI σε Χώρα των Βάσκων/Ναβάρρα· SII για μεγάλους | **Ναι** | Συμμόρφωση του Palee ως SIF ή μέσω παρόχου | P1 |
| Πορτογαλία | pt-PT | Πιστοποιημένο λογισμικό AT, ATCUD, QR, SAF-T μηνιαία | **Ναι** | Συνεργασία με πιστοποιημένο λογισμικό | P1 |
| Ρωσία | ru | 54-ФЗ online ταμεία μέσω ΟФД | **Ναι** | **Δεν προτείνεται** (κυρώσεις, πληρωμές) | — |
| Ισραήλ | he | Israel Invoices: αριθμός κατανομής για B2B > ₪5.000 | Όχι (μόνο B2B) | Μέσω τοπικού λογισμικού ή API της ITA | P2 |
| Σαουδική Αραβία | ar | ZATCA FATOORA φάση 2 | **Ναι** (αναφορά B2C σε 24 ώρες) | Μέσω παρόχου ZATCA | P2 |
| ΗΑΕ | ar | Peppol PINT AE μέσω ASP από 1/2027 | Όχι (B2C εξαιρείται προς το παρόν) | Μέσω ASP | P2 |
| Αίγυπτος | ar | ETA e-invoice (B2B) και e-receipt (B2C), σε φάσεις | Πιθανώς | Μέσω παρόχου ETA | P2 |
| Ιορδανία | ar | JoFotara | Ναι, όπου ισχύει | Μέσω παρόχου | P2 |
| ΗΒ | en | MTD for VAT (ψηφιακά βιβλία, υποβολή δηλώσεων μέσω API)· e-invoicing 4/2029 | Όχι ανά απόδειξη | Σύνδεση με Xero/QuickBooks/Sage | P1 |
| Ιρλανδία | en | Καμία σήμερα· e-invoicing και real-time reporting B2B από 11/2028 | Όχι | Σύνδεση με λογιστικό λογισμικό | P2 |
| ΗΠΑ | en | Κανένα ομοσπονδιακό· φόρος πωλήσεων ανά πολιτεία | Ναι για φόρο πωλήσεων σε κάποιες πολιτείες | Avalara/TaxJar + QuickBooks | P2 |
| Καναδάς | en, fr | Κανένα· Peppol προαιρετικό· SRM Κεμπέκ μόνο για εστίαση/ταξί | Όχι | QuickBooks/Xero | P2 |
| Αυστραλία | en | Peppol (PINT A-NZ) μόνο για B2G· B2B εθελοντικό | Όχι | Xero/MYOB | P2 |
| Νέα Ζηλανδία | en | Peppol για B2G· B2B εθελοντικό | Όχι | Xero | P2 |

---

## Ανά χώρα

### Ελλάδα: myDATA (ΑΑΔΕ) · P0
- **Τι ισχύει:** τα παραστατικά διαβιβάζονται στο myDATA. Η υποχρεωτική ηλεκτρονική τιμολόγηση B2B ξεκίνησε για επιχειρήσεις με έσοδα άνω του 1 εκατ. € στις 2/3/2026 (αρχικά 2/2/2026) και ακολουθούν όλες οι υπόλοιπες. Για τη δεύτερη φάση οι πηγές διαφωνούν: 1/10, 12/10 ή 2/11/2026. Η έκδοση γίνεται μόνο μέσω πιστοποιημένου παρόχου ηλεκτρονικής τιμολόγησης ή των δωρεάν εργαλείων της ΑΑΔΕ (Timologio, myDATAapp). Παραστατικό που εκδίδεται εκτός αυτών θεωρείται μη εκδοθέν, με πρόστιμο 50% του ΦΠΑ.
- **Για το B2C:** τα POS πρέπει να είναι διασυνδεδεμένα με ΦΗΜ ή πάροχο από το 2023. Η ΔΕΔ 1441/2026 θεωρεί τη μη διασύνδεση αυτοτελή παράβαση με πρόστιμο 10.000 €, ακόμη και όταν εκδίδονται αποδείξεις.
- **Για το Palee:** ήδη αποθηκεύεται το MARK σε τιμολόγια (`Palee.Finance`), αλλά χωρίς διασύνδεση. Πρόταση: port `FiscalDocumentGateway` με πρώτο adapter έναν πιστοποιημένο πάροχο ηλεκτρονικής τιμολόγησης. Κάθε απόδειξη συνδρομής, πακέτου ή shop εκδίδεται μέσω του παρόχου και επιστρέφει MARK και QR. Οι πληρωμές με κάρτα (CP-A1/A2) πρέπει να «δένονται» με την απόδειξη, για τη διασύνδεση POS. Ο πάροχος είναι απόφαση του ANR.
- **Πηγές:** [KPMG, αναβολή 2/2026](https://kpmg.com/us/en/taxnewsflash/news/2026/02/greece-implementation-mandatory-e-invoicing-postponed.html) · [KPMG, προθεσμίες 9/2025](https://kpmg.com/us/en/taxnewsflash/news/2025/09/greece-compliance-deadlines-electronic-invoicing.html) · [Taxually](https://www.taxually.com/blog/greece-b2b-e-invoicing-2026) · [vatcalc](https://www.vatcalc.com/greece/greece-mydata-replaces-domestic-customer-and-supplier-listings/) · [Comarch](https://www.comarch.com/trade-and-services/data-management/legal-regulation-changes/greece-mandates-b2b-e-invoicing-for-2026/) · [ΔΕΔ 1441/2026 (taxheaven)](https://www.taxheaven.gr/circulars/54727/ded-1441-2026) · [ΑΑΔΕ, απόφαση διασύνδεσης POS 12/2022](https://www.aade.gr/sites/default/files/2022-12/dt_30.12.2022._0.pdf)

### Κύπρος · P2
- **Τι ισχύει:** καμία υποχρέωση ηλεκτρονικής τιμολόγησης για B2B ή B2C το 2026, μόνο προς το Δημόσιο (Ν. 89(Ι)/2019). Το ViDA της ΕΕ θα απαιτήσει e-invoicing για ενδοκοινοτικές B2B συναλλαγές από 1/7/2030.
- **Για το Palee:** τίποτα κρατικό. Καλό export για τον λογιστή.
- **Πηγές:** [Zeno Legal](https://www.zenolegal.com/resources/cyprus-vida-e-invoicing-2026) · [ecosio](https://ecosio.com/en/compliance/cyprus/e-invoicing/) · [EY tracker 08/2026](https://www.ey.com/content/dam/ey-unified-site/ey-com/en-gl/technical/tax-guides/documents/ey-gl-e-invoicing-developments-tracker-08-2026.pdf)

### Βουλγαρία · P2
- **Τι ισχύει:** οι λιανικές πωλήσεις καταγράφονται σε φορολογικές συσκευές συνδεδεμένες με την NRA (Διάταγμα Ν-18). Τα e-shops και το λογισμικό διαχείρισης πωλήσεων (SUPTO) έχουν ειδικές απαιτήσεις. Για πληρωμές με κάρτα υπάρχουν εναλλακτικές λύσεις, αλλά οι όροι δεν βρέθηκαν. Σχέδιο νόμου (διαβούλευση ως 23/10/2026) προβλέπει υποχρεωτικό B2B e-invoicing και αναφορά σε πραγματικό χρόνο από 1/1/2028, μέσω του συστήματος NISSEF της NRA.
- **Για το Palee:** το SUPTO είναι λογισμικό που πιστοποιείται. Πιο ρεαλιστικό είναι συνεργασία με υπάρχον πιστοποιημένο SUPTO παρά να πιστοποιηθεί το Palee.
- **Πηγές:** [wtsklient, online stores](https://wtsklient.hu/2018/11/29/sales-through-online-stores/) · [BCCI, τροποποίηση Ν-18](https://www.infobusiness.bcci.bg/promulgation-of-ordinance-amending-ordinance-no-n-18-of-2006.html) · [fiscal-requirements, σχέδιο 2028](https://www.fiscal-requirements.com/news/6021-bulgaria-proposes-mandatory-e-invoicing-and-real-time-vat-reporting-from-2028) · [Sovos](https://sovos.com/regulatory-updates/global-vat/bulgaria-proposes-mandatory-e-invoicing-for-domestic-supplies/) · [vatupdate](https://www.vatupdate.com/2026/10/02/bulgaria-plans-mandatory-e-invoicing-and-digital-vat-reporting-by-2028/)

### Γερμανία · P1
- **Τι ισχύει:** τα ηλεκτρονικά ταμεία χρειάζονται τεχνική διάταξη ασφαλείας (TSE, KassenSichV, §146a AO) και δήλωση στο ELSTER από 1/1/2025 (οι υπάρχουσες έως 31/7/2025, οι νέες εντός μηνός). Όλες οι επιχειρήσεις πρέπει να **λαμβάνουν** δομημένα τιμολόγια B2B από 1/2025, ενώ η **έκδοση** γίνεται υποχρεωτική το 2027 για τις μεγαλύτερες και το 2028 για όλες (XRechnung/ZUGFeRD, EN 16931).
- **Ιδιωτικό λογισμικό που κυριαρχεί:** DATEV. Ο λογιστής σχεδόν σίγουρα δουλεύει σε DATEV, άρα ένα export σε μορφή DATEV είναι σχεδόν υποχρεωτικό στην πράξη. Για μικρές επιχειρήσεις, Lexware Office και sevdesk.
- **Για το Palee:** (α) cloud TSE μέσω παρόχου, αν το box εισπράττει στο ταμείο (CP-A2). Αν οι online πληρωμές με κάρτα χωρίς ταμείο καλύπτονται από την υποχρέωση TSE: χωρίς πηγή, θέλει φοροτεχνικό. (β) Export DATEV. (γ) Έκδοση XRechnung/ZUGFeRD για B2B τιμολόγια.
- **Πηγές:** [RetailForce, δήλωση ταμείων 2025](https://www.retailforce.cloud/germany-reporting-requirement-for-cash-registers-starting-in-july-2025/?lang=en) · [IHK Hagen](https://www.ihk.de/hagen/standortpolitik/downloads/aufzeichnungspflichten-3515740) · [fiscal-requirements, Γερμανία](https://www.fiscal-requirements.com/countries/2-germany) · [mehrwertsteuerrechner.de, E-Rechnung](https://www.mehrwertsteuerrechner.de/e-rechnung-pflicht/) · [Chift, λογιστικό λογισμικό 2026](https://www.chift.eu/blog/the-accounting-software-landscape-in-germany-a-2026-guide-for-saas-vendors) · [DATEV-Format (Frappe docs)](https://docs.frappe.io/erpnext/v12/user/manual/en/regional/germany/datev-export)

### Αυστρία · P2
- **Τι ισχύει:** υποχρέωση ταμειακής μηχανής (RKSV) πάνω από 15.000 € ετήσιο τζίρο και 7.500 € σε μετρητά, με μονάδα δημιουργίας υπογραφής, AES-256 και μοναδικό ID ταμείου. Υποχρέωση έκδοσης απόδειξης για κάθε πληρωμή σε μετρητά από 1/1/2016. Αν οι πληρωμές με κάρτα μετρούν ως «μετρητά» (Barumsätze): χωρίς πηγή σε αυτή την έρευνα.
- **Για το Palee:** cloud υπογραφή RKSV μέσω παρόχου, μόνο αν μπει η Αυστρία στους στόχους.
- **Πηγές:** [USP.gv.at, Registrierkassen](https://www.usp.gv.at/themen/steuern-finanzen/steuerliche-rechte-und-pflichten/registrierkassen.html) · [BMF](https://www.bmf.gv.at/themen/steuern/fuer-unternehmen/registrierkassen.html) · [WKO](https://www.wko.at/oe/austriaguides/registrierkassenpflicht.pdf) · [finanz.at](https://www.finanz.at/ratgeber/registrierkassenpflicht)

### Ελβετία · P2
- **Τι ισχύει:** καμία υποχρέωση B2B e-invoicing και η Ελβετία δεν υπάγεται στο ViDA. Δομημένα τιμολόγια ζητούνται μόνο από την ομοσπονδιακή διοίκηση, για συμβάσεις άνω των 5.000 CHF. Το QR-bill είναι πρότυπο πληρωμής (από 1/10/2022 ισχύουν μόνο QR-bills), όχι e-invoicing.
- **Ιδιωτικό λογισμικό:** bexio (δηλώνει 80.000+ πελάτες, δική του δήλωση).
- **Για το Palee:** QR-bill στα τιμολόγια και export προς bexio, μόνο αν μπει η Ελβετία στους στόχους.
- **Πηγές:** [econnect](https://econnect.eu/en/docs/knowledge/regulations/europe/switzerland) · [Sovos, QR-bill](https://sovos.com/blog/vat/switzerland-introduces-qr-bill-to-increase-automation-of-payment-data) · [bexio, QR invoice](https://www.bexio.com/en-CH/qr-invoice)

### Γαλλία · P1
- **Τι ισχύει:** (α) **NF525:** οι επιχειρήσεις που εισπράττουν από ιδιώτες με λογισμικό ή σύστημα ταμείου χρειάζονται πιστοποιητικό από διαπιστευμένο φορέα ή βεβαίωση του εκδότη του λογισμικού. Η κατάργηση της αυτο-βεβαίωσης ακυρώθηκε με τον νόμο 2026-103 της 19/2/2026. Πρόστιμο 7.500 € ανά λογισμικό χωρίς δικαιολογητικό. (β) **E-invoicing:** από 1/9/2026 όλες οι επιχειρήσεις πρέπει να λαμβάνουν ηλεκτρονικά τιμολόγια και οι μεγάλες να τα εκδίδουν. Οι ΜμΕ ακολουθούν από 1/9/2027. Τα τιμολόγια περνούν από πιστοποιημένες πλατφόρμες (Plateformes Agréées). (γ) **E-reporting:** οι πωλήσεις B2C και τα δεδομένα πληρωμών αναφέρονται στη DGFiP.
- **Για το Palee:** το Palee εισπράττει από ιδιώτες, άρα πιθανότατα πέφτει στο NF525. Χρειάζεται τουλάχιστον βεβαίωση εκδότη (απαραβίαστο, ασφάλεια, διατήρηση και αρχειοθέτηση δεδομένων). Για e-invoicing και e-reporting: σύνδεση με μία PA.
- **Πηγές:** [Kohen Avocats](https://kohenavocats.fr/?p=1995962) · [Independant.io, NF525](https://independant.io/norme-nf525/) · [Banqup, μετά την 1/9/2026](https://www.banqup.com/resources/blog/france-s-e-invoicing-reform-where-businesses-stand-after-1-september-2026) · [Axway](https://blog.axway.com/product-insights/b2b-integration/einvoicing/france-e-invoicing-reform-2026) · [VATit](https://vatit.com/fr/e-invoicing-guide/france/)

### Βέλγιο · P2
- **Τι ισχύει:** υποχρεωτικό δομημένο e-invoicing (Peppol BIS, EN 16931) για εγχώριες B2B συναλλαγές από 1/1/2026. Τα PDF δεν γίνονται πλέον δεκτά για αυτές. Το B2C είναι εκτός. Η αναφορά σχεδόν σε πραγματικό χρόνο έρχεται 1/1/2028.
- **Για το Palee:** αποστολή B2B τιμολογίων μέσω Peppol (κοινό με ΗΑΕ, Αυστραλία, Νέα Ζηλανδία, Ιρλανδία, Ολλανδία). Ένας adapter Peppol εξυπηρετεί πολλές χώρες.
- **Πηγές:** [TrueCommerce](https://www.truecommerce.com/blog/e-invoicing-in-belgium-your-guide-to-the-2026-mandate/) · [N2F](https://www.n2f.com/blog/en/peppol-in-belgium-how-it-works-requirements-and-key-dates/) · [Invopop docs](https://docs.invopop.com/compliance/belgium)

### Ολλανδία · P2
- **Τι ισχύει:** σήμερα καμία υποχρέωση. Η κυβέρνηση ανακοίνωσε στις 11/9/2026 υποχρεωτικό B2B e-invoicing από 1/7/2030, με εγχώρια ψηφιακή αναφορά από 1/7/2031.
- **Ιδιωτικό λογισμικό:** χωρίς πηγή σε αυτή την έρευνα (συχνά αναφέρονται Exact και Moneybird).
- **Πηγές:** [Sovos, επιβεβαίωση 2030](https://sovos.com/regulatory-updates/global-vat/netherlands-confirms-plans-for-mandatory-e-invoicing-from-july-2030/) · [Sovos](https://sovos.com/blog/global-vat/netherlands-b2b-e-invoicing-mandate-2030) · [KPMG 5/2026](https://kpmg.com/us/en/taxnewsflash/news/2026/05/tnf-netherlands-proposed-e-invoicing-and-digital-reporting-framework-under-vida.html)

### Ιταλία · P1
- **Τι ισχύει:** όλα τα τιμολόγια περνούν από το Sistema di Interscambio (SdI). Οι λιανικές εισπράξεις (corrispettivi) αποστέλλονται ηλεκτρονικά μέσω registratore telematico (RT) ή της διαδικτυακής υπηρεσίας της Agenzia delle Entrate. Από το 2026 κάθε μέσο ηλεκτρονικής πληρωμής, **και οι διαδικτυακές πλατφόρμες και εφαρμογές**, πρέπει να συνδεθεί με το RT μέσω της πύλης «Fatture e Corrispettivi» (Ν. 207/2024). Η λειτουργία άνοιξε 5/3/2026.
- **Για το Palee:** σύνδεση με πιστοποιημένο intermediario για SdI και corrispettivi. Οι online πληρωμές του Palee πρέπει να συνδεθούν με το RT του box.
- **Πηγές:** [Agenda Digitale](https://www.agendadigitale.eu/documenti/fisco-digitale-guida-agli-strumenti-fatturazione-ricevute-e-pagamenti/) · [Studio Pizzano, οδηγός POS–RT](https://www.studiopizzano.it/collegamento-pos-registratore-telematico-guida/) · [Fiscal Focus, 5/3/2026](https://www.fiscal-focus.it/news-24/ore-08-37-pos-rt-dal-5-marzo-2026-parte-l-abbinamento-sul-portale-ae,3,182059) · [Cloudbeds](https://myfrontdesk.cloudbeds.com/hc/en-us/articles/48475512431003)

### Ισπανία · P1
- **Τι ισχύει:** το **VeriFactu** μετατέθηκε (RDL 15/2025) στην 1/1/2027 για εταιρείες και στην 1/7/2027 για ελεύθερους επαγγελματίες και λοιπούς. Μία πηγή (5/10/2026) αναφέρει νέα αναβολή ως τον 10/2028, ανεπιβεβαίωτη. Η Χώρα των Βάσκων και η Ναβάρρα έχουν δικό τους TicketBAI. Οι μεγάλοι αναφέρουν μέσω SII. Οι κατασκευαστές λογισμικού έπρεπε να είναι έτοιμοι από 29/7/2025.
- **Για το Palee:** το Palee εκδίδει παραστατικά, άρα είναι «σύστημα τιμολόγησης» (SIF). Πρέπει είτε να συμμορφωθεί το ίδιο με το VeriFactu (εγγραφές με hash και QR, προαιρετική αποστολή στην AEAT) είτε να εκδίδει μέσω συμμορφωμένου παρόχου.
- **Πηγές:** [KPMG](https://kpmg.com/us/en/taxnewsflash/news/2025/12/tnf-spain-verifactu-invoicing-system-delayed-to-2027.html) · [BDO](https://www.bdo.global/en-gb/insights/tax/indirect-tax/spain-veri-factu-obligation-postponed-until-2027) · [Fonoa](https://www.fonoa.com/resources/blog/spain-delays-verifactu-compliance-deadlines-to-2027) · [Mallorca.com, νέα αναβολή (ανεπιβεβαίωτη)](https://www.mallorca.com/en/magazin/news/verifactu-delay-spain)

### Πορτογαλία · P1
- **Τι ισχύει:** κάθε τιμολόγιο εκδίδεται από λογισμικό πιστοποιημένο από την AT, με μοναδικό κωδικό ATCUD και QR, και αναφέρεται μηνιαία με SAF-T (ως τις 5 του επόμενου μήνα). Για τα PDF τιμολόγια απαιτείται ειδική ηλεκτρονική υπογραφή από 1/1/2027. Οι πηγές διαφωνούν για το αν το δομημένο B2B είναι ήδη υποχρεωτικό.
- **Για το Palee:** η πιστοποίηση από την AT είναι βαριά. Πιο ρεαλιστικό είναι να εκδίδει μέσω πιστοποιημένου λογισμικού με API.
- **Πηγές:** [Zone & Co](https://www.zoneandco.com/articles/e-invoicing-portugal-compliance-guide) · [Invopop](https://docs.invopop.com/compliance/portugal) · [vatcalc](https://www.vatcalc.com/portugal/portugal-delays-electronic-invoice-format-again/)

### Ρωσία · δεν προτείνεται
- **Τι ισχύει:** κάθε πληρωμή από ιδιώτη (μετρητά, κάρτα, QR) περνά από online ταμείο και OFD προς την Ομοσπονδιακή Φορολογική Υπηρεσία (54-ФЗ). Πρόστιμα 25–50% του ποσού που δεν καταγράφηκε.
- **Γιατί όχι:** οι Visa/Mastercard σταμάτησαν να εξυπηρετούν ρωσικές κάρτες το 2022 και το Stripe δεν δέχεται χρήστες στη Ρωσία. Χρειάζονται ρωσικοί πάροχοι (YooKassa, CloudPayments) και υπάρχει ζήτημα κυρώσεων που θέλει νομική εξέταση. Η ρωσική μετάφραση εξυπηρετεί ρωσόφωνους σε άλλες χώρες (π.χ. Κύπρος, Ισραήλ, Βαλτική) χωρίς να χρειάζεται διασύνδεση με τη Ρωσία.
- **Πηγές:** [Saby, 54-ФЗ](https://saby.ru/ofd/54_fz) · [izi.is](https://izi.is/wiki/en/legal/cash-register-russia/) · [dtf.ru, Stripe και Ρωσία](https://dtf.ru/howto/5216984-kak-oplatit-stripe-iz-rossii) · [paymentproviders.io](https://paymentproviders.io/russian-payment-providers)

### Ισραήλ · P2
- **Τι ισχύει:** «Israel Invoices»: για τιμολόγια B2B πάνω από ένα όριο, ο εκδότης παίρνει αριθμό κατανομής από τη φορολογική αρχή (API ή πύλη) πριν το εκδώσει. Χωρίς αυτόν ο αγοραστής δεν εκπίπτει τον ΦΠΑ. Το όριο έπεσε στα ₪5.000 από 1/6/2026. Οι παλαιότερες πηγές δίνουν άλλο χρονοδιάγραμμα.
- **Για το box:** αφορά μόνο B2B (εταιρικές συνδρομές). Οι συνδρομές ιδιωτών δεν χρειάζονται αριθμό.
- **Ιδιωτικό λογισμικό:** τοπικά εργαλεία τιμολόγησης (π.χ. Green Invoice/Morning, iCount) χρησιμοποιούνται ευρέως από μικρές επιχειρήσεις. Χωρίς πηγή για μερίδιο αγοράς.
- **Πηγές:** [VATit](https://vatit.com/e-invoicing-guide/israel/) · [Avalara](https://www.avalara.com/us/en/blog/israel-invoice-allocation-number-mandate.html) · [Banqup](https://www.banqup.com/en-be/resources/blog/israel-s-clearance-regime-full-steam-ahead-despite-challenges) · [beancount.io, ₪5.000](https://beancount.io/blog/2026/09/22/israel-invoice-allocation-number-5000-nis-osek-murshe-b2b-guide)

### Σαουδική Αραβία · P2
- **Τι ισχύει:** στη φάση 2 της FATOORA (ZATCA), τα B2B τιμολόγια εγκρίνονται σε πραγματικό χρόνο πριν την έκδοση. Τα B2C αναφέρονται εντός 24 ωρών, και κάθε απόδειξη έχει QR. Η ένταξη γίνεται σε κύματα: το 24ο κύμα (τζίρος > 375.000 SAR) ως 30/6/2026, το 25ο (> 187.500 SAR) ως 1/2/2027.
- **Πηγές:** [Sovos](https://sovos.com/regulatory-updates/global-vat/saudi-arabia-e-invoicing-phase-2-update/) · [ClearTax, κύμα 24](https://www.cleartax.com/sa/zatca-wave24-einvoicing-in-saudi-arabia) · [Wafeq](https://www.wafeq.com/en-sa/tax-and-reporting/which-zatca-wave-am-i-in-deadlines-and-what-to-do) · [vatcalc](https://vatcalc.com/saudi-arabia/saudi-arabia-2023-mandatory-e-invoices-fatoorah-july-2023-wave-2)

### ΗΑΕ · P2
- **Τι ισχύει:** πιλοτική φάση από 1/7/2026. Επιχειρήσεις με έσοδα ≥ 50 εκατ. AED υποχρεούνται από 1/1/2027, οι υπόλοιπες από 1/7/2027. Η ανταλλαγή γίνεται μέσω διαπιστευμένου παρόχου (ASP) στο Peppol (PINT AE). Το B2C εξαιρείται μέχρι νεωτέρας.
- **Πηγές:** [KPMG](https://kpmg.com/us/en/taxnewsflash/news/2025/10/uae-framework-scope-implementation-e-invoicing-system.html) · [Comarch](https://www.comarch.com/trade-and-services/data-management/legal-regulation-changes/uae-announces-official-e-invoicing-mandate-with-a-phased-rollout-from-2026/) · [VATit](https://vatit.com/e-invoicing-guide/united-arab-emirates/)

### Αίγυπτος · P2
- **Τι ισχύει:** χωριστά συστήματα για B2B/B2G (e-invoice) και B2C (e-receipt) της ETA. Το e-receipt επεκτείνεται σε φάσεις, με λίστες επιχειρήσεων. Η τελευταία φάση που βρέθηκε ισχύει από 15/11/2025. Αν ένα box είναι υπόχρεο φαίνεται από την αναζήτηση στη λίστα της ETA. Δεν βρέθηκε ειδική αναφορά σε γυμναστήρια.
- **Πηγές:** [KPMG 7/2025](https://kpmg.com/us/en/taxnewsflash/news/2025/07/tnf-egypt-new-taxpayers-required-to-comply-with-mandate-to-issue-electronic-receipts-for-b2c-transactions.html) · [Comarch](https://www.comarch.com/trade-and-services/data-management/legal-regulation-changes/egypt-expands-e-receipt-requirements-for-b2c-transactions-from-september-2025/) · [Invoice Data Extraction, οδηγός 2026](https://invoicedataextraction.com/blog/egypt-electronic-receipt-compliance-guide)

### Ιορδανία · P2
- **Τι ισχύει:** τα τιμολόγια επικυρώνονται από την πλατφόρμα JoFotara πριν θεωρηθούν νόμιμα. Οι πηγές διαφωνούν για τις φάσεις και για τις ΜμΕ.
- **Άλλες αραβόφωνες χώρες (π.χ. Μαρόκο, Λίβανος):** δεν βρέθηκαν στοιχεία.
- **Πηγές:** [VATit](https://businessbonus.vatit.com/?p=90318) · [ClearTax](https://www.cleartax.com/jo/e-invoicing-software) · [Edicom](https://edicomgroup.com/blog/jordan-prepares-to-launch-the-electronic-invoice)

### Ηνωμένο Βασίλειο · P1 (για αγγλόφωνες αγορές)
- **Τι ισχύει:** το Making Tax Digital for VAT απαιτεί ψηφιακά βιβλία και υποβολή δηλώσεων ΦΠΑ από λογισμικό που συνδέεται με την HMRC μέσω API. Αυτό δεν είναι αναφορά ανά απόδειξη. Το υποχρεωτικό e-invoicing για όλα τα τιμολόγια ΦΠΑ έρχεται τον 4/2029.
- **Στην πράξη:** οι μικρές επιχειρήσεις κάνουν MTD μέσω λογιστικού λογισμικού (Xero, QuickBooks, Sage). Χωρίς πηγή για μερίδια.
- **Για το Palee:** σύνδεση με Xero και QuickBooks (κοινή με ΗΠΑ, Καναδά, Αυστραλία, ΝΖ, Ιρλανδία), όχι απευθείας με την HMRC.
- **Πηγές:** [KPMG UK, Autumn Budget](https://kpmg.com/uk/en/insights/tax/tmd-autumn-budget-electronic-invoicing.html) · [Marosa, HMRC roadmap 2026](https://marosavat.com/vat-news/hmrc-transformation-roadmap-2026-update) · [Stripe, e-invoicing UK](https://stripe.com/ae/resources/more/e-invoicing-in-the-uk)

### Ιρλανδία · P2
- **Τι ισχύει:** σήμερα τίποτα. Από 11/2028 οι μεγάλες εταιρείες κάνουν B2B e-invoicing με αναφορά σχεδόν σε πραγματικό χρόνο, και όλες πρέπει να μπορούν να λαμβάνουν δομημένα τιμολόγια. Ακολουθούν 11/2029 και 7/2030 (ViDA). Το δίκτυο είναι Peppol.
- **Πηγές:** [DCU Business School](https://business.dcu.ie/vat-modernisation-implementation-of-e-invoicing-in-ireland/) · [Sage IE](https://www.sage.com/en-ie/blog/e-invoicing-what-business-should-do-now) · [Comarch](https://aplikujonline.comarch.pl/trade-and-services/data-management/legal-regulation-changes/ireland-sets-timeline-for-mandatory-b2b-e-invoicing-and-real-time-vat-reporting)

### ΗΠΑ · P2
- **Τι ισχύει:** κανένα ομοσπονδιακό σύστημα. Το σημαντικό είναι ο **φόρος πωλήσεων ανά πολιτεία**: περίπου οι μισές πολιτείες φορολογούν τις συνδρομές γυμναστηρίων (π.χ. Τενεσί ναι). Η Καλιφόρνια και η Νέα Υόρκη τις εξαιρούν, αλλά η Νέα Υόρκη πόλη επιβάλλει 4,5%. Οι online συνδρομές φορολογούνται συχνά ως ψηφιακές υπηρεσίες. Οι κανόνες διαφέρουν ανά τύπο εγκατάστασης.
- **Ιδιωτικό λογισμικό:** Avalara ή TaxJar για υπολογισμό φόρου, QuickBooks για λογιστική.
- **Πηγές:** [TaxJar](https://blog.taxjar.com/06-21-sales-tax-fitness-memberships/) · [Avalara, Τενεσί](https://www.avalara.com/us/en/blog/taxable-and-exempt-fitness-fees-in-tennessee-wacky-tax-wednesday.html) · [Avalara, Funky Fitness Taxes](https://www.avalara.com/us/en/blog/2016/03/funky-fitness-taxes-wacky-tax-wednesday.html)

### Καναδάς · P2
- **Τι ισχύει:** κανένα υποχρεωτικό e-invoicing. Το Peppol είναι προαιρετικό (εκτός ομοσπονδιακών προμηθειών). Η CRA μελέτησε το θέμα, αλλά δεν συνέχισε στο πλάνο 2026–27. Στο Κεμπέκ υπάρχει fiscalisation μόνο για εστίαση και ταξί.
- **Για το Palee:** QuickBooks/Xero, και σωστός υπολογισμός GST/HST/QST.
- **Πηγές:** [Fonoa](https://www.fonoa.com/resources/country-tax-guides/canada/e-invoicing-and-digital-reporting) · [Basware](https://basware.com/en/compliance-map/canada) · [e-invoice.app](https://www.e-invoice.app/countries/CA)

### Αυστραλία · P2
- **Τι ισχύει:** Peppol (PINT A-NZ) υποχρεωτικό μόνο για ομοσπονδιακούς φορείς. Καμία υποχρέωση B2B, και το «Business E-Invoicing Right» δεν ψηφίστηκε. 400.000+ επιχειρήσεις είναι εγγεγραμμένες στο Peppol.
- **Για το Palee:** Xero/MYOB (χωρίς πηγή για μερίδια).
- **Πηγές:** [Zone & Co](https://www.zoneandco.com/articles/e-invoicing-in-australia-compliance-guide) · [Invopop](https://invopop.com/coverage/australia.md)

### Νέα Ζηλανδία · P2
- **Τι ισχύει:** καμία υποχρέωση B2B. Οι κρατικοί φορείς στέλνουν και λαμβάνουν e-invoices από 1/2026. Οι μεγάλοι προμηθευτές (> 33 εκατ. NZD) στέλνουν e-invoices στο Δημόσιο από 1/1/2027. Το GST δηλώνεται περιοδικά, όχι σε πραγματικό χρόνο.
- **Πηγές:** [Sovos](https://sovos.com/regulatory-updates/vat/new-zealand-expands-b2g-e-invoicing-framework/) · [Zone & Co](https://www.zoneandco.com/articles/e-invoicing-new-zealand-compliance-guide) · [Comarch](https://www.comarch.com/trade-and-services/data-management/legal-regulation-changes/new-zealand-to-mandate-b2g-e-invoicing-for-large-suppliers/)

---

## Τι σημαίνει για την αρχιτεκτονική του Palee

1. **Ένα port, πολλοί adapters.** `FiscalDocumentGateway` στο domain των οικονομικών: «έκδωσε φορολογικό παραστατικό για αυτή την πληρωμή» → επιστρέφει αναγνωριστικό της αρχής (MARK, ATCUD, αριθμό κατανομής, SdI id), QR και κατάσταση. Ένας adapter ανά χώρα ή ανά πάροχο. Το πεδίο «legal receipt reference» που υπάρχει ήδη γίνεται η γενική μορφή αυτού.
2. **Μέσω παρόχων, σχεδόν παντού.** Σε Ελλάδα, Ιταλία, Πορτογαλία, Γαλλία, ΗΑΕ, Σαουδική Αραβία ο νόμος ή η πρακτική οδηγεί σε πιστοποιημένο ενδιάμεσο. Η πιστοποίηση του ίδιου του Palee έχει νόημα μόνο για το NF525 (βεβαίωση εκδότη) και ίσως για το VeriFactu.
3. **Ένας adapter Peppol** καλύπτει τα B2B τιμολόγια σε Βέλγιο, Ιρλανδία, Ολλανδία, ΗΑΕ, Αυστραλία, ΝΖ και, μέσω EN 16931, τη Γερμανία (XRechnung). Εξετάστε έναν «πολυεθνικό» πάροχο (π.χ. Invopop ή Fonoa, που καλύπτουν πολλές χώρες με ένα API) πριν χτιστούν adapters μία-μία χώρα. Χρειάζεται αξιολόγηση κόστους.
4. **Exports λογιστικής** (DATEV, Xero, QuickBooks, Sage, bexio) για τις χώρες χωρίς κρατικό σύστημα. Αυτή η «διασύνδεση» πουλάει περισσότερο από οποιοδήποτε κρατικό API.
5. **Φορολογικοί κανόνες ανά χώρα και πολιτεία:** συντελεστές ΦΠΑ/GST, φόρος πωλήσεων στις ΗΠΑ (μέσω Avalara ή TaxJar), εξαιρέσεις.
6. **Η πληρωμή και το παραστατικό δένονται** (CP-A1/A2): στην Ελλάδα (POS–ΦΗΜ) και στην Ιταλία (POS–RT) ο νόμος ζητά ρητά τη σύνδεση της κάρτας με την απόδειξη.

## Προτεινόμενη σειρά

1. **Ελλάδα (myDATA μέσω παρόχου):** η αγορά εκκίνησης, με υποχρέωση που ισχύει ήδη.
2. **Exports λογιστικής** (Xero, QuickBooks, DATEV): φθηνά, καλύπτουν πολλές αγγλόφωνες χώρες και τη Γερμανία.
3. **Η επόμενη χώρα-στόχος**, όταν επιλεγεί: η Κύπρος δεν θέλει τίποτα κρατικό. Ιταλία, Πορτογαλία, Ισπανία και Γαλλία θέλουν σημαντική δουλειά πριν από το πρώτο box.
4. **Peppol** μόλις υπάρξουν B2B πελάτες σε Βέλγιο, Γερμανία ή ΗΑΕ.

**Απόφαση ANR:** ποιες χώρες είναι στόχος μετά την Ελλάδα. Αυτό καθορίζει ποιοι adapters χτίζονται και πότε.
