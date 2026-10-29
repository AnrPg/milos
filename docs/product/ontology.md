# Palee ontology: canonical terms (English · Ελληνικά)

Status: **draft, 2026-10-25**, waiting for ANR's choices in §5. Once approved it is the
source of truth for every name in the UI, the docs and code comments; the code keeps its
table and module names (column «Code»), which never appear in the UI.

How to use it:
- One thing, one name, in each language. If a screen needs a name that is not here, add it
  here first.
- «Not to be confused with» lists the near names that caused confusion so far.
- Greek uses the English loanword only where Greek users already say it (Box, club, coach, PR, WOD).
  Abbreviations that Greeks don't use (PT) and words they don't know (squad) are written in Greek.
- A person's role is always a word for the person, never the department (λογιστής, not «Λογιστήριο»).
- Never write a bare "member" / «μέλος»: always say what of (box member, club member).

## 1. The layers at a glance

1. **Platform**: Palee and the Palee team.
2. **Accounts and profiles**: who signs in, and who they appear as.
3. **Businesses**: the providers people train with (box, independent coach) and event organisers.
4. **Inside a business**: branches, roles, staff, clients, plans.
5. **Community spaces**: clubs and the channels inside them.
6. **Person-to-person relations**: follows, buddies, training partners, check-in buddies, coaching.
7. **Conversations**: everything in Μηνύματα.
8. **Outside parties**: partner businesses (perks), corporate clients, guests.

## 2. Graph (English)

```mermaid
flowchart TB
  subgraph PLATFORM["Platform"]
    PALEE["Palee"]
    TEAM["Palee team (vendor)"]
  end

  subgraph ACCOUNTS["Accounts"]
    LOGIN["Account (email + password)"]
    PROFILE["Profile (@handle + display name)"]
  end

  subgraph BUSINESSES["Businesses"]
    BIZ["Business"]
    BOX["Box (gym, studio, dance academy…)"]
    INDIE["Independent coach"]
    ORG["Organiser"]
    BRANCH["Branch"]
  end

  subgraph ROLES["Roles in a business"]
    STAFF["Staff: owner · admin · coach (head coach) · front desk · accountant · cleaning"]
    CLIENT["Client: box member · athlete"]
  end

  subgraph SPACES["Community spaces"]
    CLUB["Club: box club · open club"]
    CHANNEL["Channel"]
    GROUP["Member group (member-made)"]
    SQUAD["PT squad (coach + own clients)"]
    EVENT["Event"]
  end

  subgraph RELATIONS["Between people"]
    FOLLOW["Follow"]
    BUDDIES["Buddies (follow each other)"]
    TPARTNER["Training partner (mutual match in a club)"]
    CHECKIN["Check-in buddy (support on request)"]
    COACHING["Coaching (coach ↔ client)"]
  end

  subgraph OUTSIDE["Outside parties"]
    PERKP["Partner business (perks)"]
    CORP["Corporate client"]
    GUEST["Guest · trial visitor"]
  end

  TEAM -- runs --> PALEE
  TEAM -- activates --> BIZ
  LOGIN -- holds up to 3 --> PROFILE
  BIZ -- is a --> BOX
  BIZ -- is a --> INDIE
  BIZ -- is a --> ORG
  BOX -- has 1..n --> BRANCH
  PROFILE -- has a role in --> BIZ
  STAFF -. scoped to .-> BRANCH
  BIZ -- has exactly 1 --> CLUB
  BOX -- runs --> CLUB
  CLUB -- contains --> CHANNEL
  CHANNEL -- kind --> GROUP
  CHANNEL -- kind --> SQUAD
  CLUB -- holds --> EVENT
  ORG -- hosts --> EVENT
  PROFILE -- follows --> PROFILE
  FOLLOW -- both ways = --> BUDDIES
  CLUB -- where people find --> TPARTNER
  PROFILE -- picks --> CHECKIN
  STAFF -- coach --> COACHING
  COACHING -- client --> CLIENT
  SQUAD -- only clients of --> COACHING
  PERKP -- offers perks to clients of --> BIZ
  CORP -- pays memberships at --> BIZ
  GUEST -- visits --> EVENT
```

## 3. Γράφος (Ελληνικά)

```mermaid
flowchart TB
  subgraph PLATFORM["Πλατφόρμα"]
    PALEE["Palee"]
    TEAM["Ομάδα Palee (vendor)"]
  end

  subgraph ACCOUNTS["Λογαριασμοί"]
    LOGIN["Λογαριασμός (email + κωδικός)"]
    PROFILE["Προφίλ (@handle + όνομα)"]
  end

  subgraph BUSINESSES["Επιχειρήσεις"]
    BIZ["Επιχείρηση"]
    BOX["Box (γυμναστήριο, studio, σχολή χορού…)"]
    INDIE["Ανεξάρτητος coach"]
    ORG["Διοργανωτής"]
    BRANCH["Παράρτημα"]
  end

  subgraph ROLES["Ρόλοι σε επιχείρηση"]
    STAFF["Προσωπικό: ιδιοκτήτης · διαχειριστής · coach (head coach) · υπάλληλος υποδοχής · λογιστής · προσωπικό καθαριότητας"]
    CLIENT["Πελάτης: μέλος box · αθλητής"]
  end

  subgraph SPACES["Χώροι κοινότητας"]
    CLUB["Club: club του box · ανοιχτό club"]
    CHANNEL["Κανάλι"]
    GROUP["Ομάδα μελών (από μέλη)"]
    SQUAD["Ομάδα του coach (coach + δικοί του πελάτες)"]
    EVENT["Εκδήλωση"]
  end

  subgraph RELATIONS["Μεταξύ ανθρώπων"]
    FOLLOW["Ακολουθώ"]
    BUDDIES["Φιλαράκια (ακολουθούν ο ένας τον άλλο)"]
    TPARTNER["Συναθλητής (αμοιβαίο ταίριασμα σε club)"]
    CHECKIN["Φιλαράκι στήριξης (στήριξη όταν τη ζητήσω)"]
    COACHING["Coaching (coach ↔ πελάτης)"]
  end

  subgraph OUTSIDE["Τρίτοι"]
    PERKP["Συνεργάτης (προσφορές)"]
    CORP["Εταιρικός πελάτης"]
    GUEST["Καλεσμένος · δοκιμαστικό"]
  end

  TEAM -- λειτουργεί --> PALEE
  TEAM -- ενεργοποιεί --> BIZ
  LOGIN -- έχει έως 3 --> PROFILE
  BIZ -- είναι --> BOX
  BIZ -- είναι --> INDIE
  BIZ -- είναι --> ORG
  BOX -- έχει 1..n --> BRANCH
  PROFILE -- έχει ρόλο σε --> BIZ
  STAFF -. περιορίζεται σε .-> BRANCH
  BIZ -- έχει ακριβώς 1 --> CLUB
  BOX -- τρέχει --> CLUB
  CLUB -- περιέχει --> CHANNEL
  CHANNEL -- είδος --> GROUP
  CHANNEL -- είδος --> SQUAD
  CLUB -- φιλοξενεί --> EVENT
  ORG -- διοργανώνει --> EVENT
  PROFILE -- ακολουθεί --> PROFILE
  FOLLOW -- και αντίστροφα = --> BUDDIES
  CLUB -- εκεί βρίσκεις --> TPARTNER
  PROFILE -- διαλέγει --> CHECKIN
  STAFF -- coach --> COACHING
  COACHING -- πελάτης --> CLIENT
  SQUAD -- μόνο πελάτες του --> COACHING
  PERKP -- προσφορές σε πελάτες της --> BIZ
  CORP -- πληρώνει συνδρομές σε --> BIZ
  GUEST -- έρχεται σε --> EVENT
```

## 4. Glossary

Terms marked **(proposed)** change today's wording; see §5. Everything else matches the app.

### 4.1 Platform and accounts

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Palee | Palee | `Palee` | The app and the company behind it. | Hosted at palee.app; the infrastructure was renamed too (TD-109). |
| Palee team | Ομάδα Palee | `vendor` role, `/platform` | The people who run Palee: activate businesses, set plans, handle password resets. Shown as "Palee" to users. (ADR-089) | Business owner. "Vendor" is a code word only. |
| Account | Λογαριασμός | `logins` | One email and one password. Holds up to 3 profiles. (ADR-187) | Profile. |
| Profile | Προφίλ | `users` | Who you appear as: unique Latin **@handle** plus a free **display name**. Everything social and every role hangs on a profile. | Account. |
| Mock person | Εικονικό άτομο | `users.demo_organization_id` | A fake member created for a business in demo mode. Never visible outside it. (ADR-184) | Trial visitor, guest. |

### 4.2 Businesses

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Business | Επιχείρηση | `organizations` (tenant) | Umbrella for anyone who runs things on Palee. Each has one kind below, a slug, a club and a plan. Demo until the Palee team activates it. | "Organization", "provider", "tenant" are code words. |
| Box | Box | `provider_kind: gym` | A place people train at: gym, CrossFit box, studio, **dance academy**, martial-arts school. What it offers is described by discipline tags, not by a separate kind. | Club (the box's community space). **(proposed)**: one word, "Box", replaces "Gym" / «Γυμναστήριο» in member screens. |
| Independent coach | Ανεξάρτητος coach | `provider_kind: coach` | A coach with their own clients and no box (the solo-coach tier, ADR-170). Same person can also be staff at a box. | **(proposed)** replaces "Personal coach", "Solo coach", «Προσωπικός coach», «Ανεξάρτητος προπονητής». |
| Organiser | Διοργανωτής | `provider_kind: organiser` | The hidden one-person business created when someone hosts an event «Ως εγώ». (ADR-185) | Co-host. |
| Co-host | Συνδιοργανωτής | `event_cohosts` | Another business that agrees to co-run an event. | Organiser. |
| Branch | Παράρτημα | `facility_locations` | One physical location of a box. Staff can be limited to some branches. (ADR-186) | **(proposed)** replaces «Κατάστημα», which also means the e-shop. |
| Branch manager | Υπεύθυνος παραρτήματος | role preset | Admin rights limited to chosen branches. | Owner. |
| Space | Χώρος | `spaces` | A room or area of a branch (or of the whole box): where classes take place, what the cleaning staff clean, where the equipment stands. Can be made unavailable for a time. (ADR-202) | Branch («Παράρτημα», never «Χώρος»); Club and community spaces (§4.4). Was "cleaning area". |
| Floor plan | Κάτοψη | `space_floor_plans` | An image of one floor of a branch, with the spaces drawn on it. A branch can have several. (ADR-202) | Map (Around). |
| Plan (Palee) | Πακέτο Palee | `platform_plans` | What a business pays Palee. | Subscription package (what clients pay the business). |
| Subscription package | Πακέτο συνδρομής | `membership_packages`, `package_type` | What a client buys or is given by a box: recurring membership, visit pack, trial, season, corporate. Always the full name, never a bare "package" / «πακέτο». Trial type: "Trial" / «Δοκιμαστικό» (never «Δίκη»). | Plan (Palee), personal training package. |

### 4.3 Roles inside a business

| English | Ελληνικά | Code | What it is |
|---|---|---|---|
| Staff | Προσωπικό | staff roles | Anyone with one of the roles below. Opens the console by default; «Διαχείριση» switches back from the social app. |
| Owner | Ιδιοκτήτης | `owner` | Everything, always all branches. |
| Admin | Διαχειριστής | `admin` | Runs the business; can be branch-scoped. |
| Coach | Coach | `coach` | Leads classes, coaches own clients. |
| Head coach | Head coach | `coach_scope: all` | A coach who sees and coaches every client, not only their own. |
| Front desk | Υπάλληλος υποδοχής | `front_desk` | Check-in, bookings, selling packages at the desk. (ADR-102) |
| Accountant | Λογιστής | `accountant` | Money only. |
| Cleaning staff | Προσωπικό καθαριότητας | `janitor` | The cleaning log only. |
| Client | Πελάτης | member or athlete role | Someone who trains with the business. Umbrella word for the two below. |
| Box member | Μέλος box | `member` | Client of a box with a membership or package. Where the box is known, name it: "Member of Box Kypseli" / «Μέλος στο Box Kypseli». Never a bare "Member" / «Μέλος». |
| Athlete | Αθλητής | `athlete` | Client who gets **personal programming** from a coach. |
| Personal link | Προσωπικός σύνδεσμος | `registration_invitations` | One-time invitation for one person, any role including staff. |
| Join links | Σύνδεσμοι εγγραφής | `organization_settings.join_link` | Public links, one per client role, each on or off on its own: «Σύνδεσμος για μέλη box» (`/join/<slug>`) and «Σύνδεσμος για αθλητές» (`/join/<slug>/athlete/<key>`). The link sets the role, never the visitor. (ADR-216) |

### 4.4 Community spaces

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Club | Club | `community_clubs` | A space with club members («μέλη club»), a feed, channels and events. Shown as a bubble in the club bar. | Box (the business). |
| Box club | Club του box | `kind: gym` | Every business has exactly one. Its members are the box's active clients; its staff are the box's staff. Named after the box. | |
| Open club | Ανοιχτό club | `kind: open` | A club staff create for a theme (e.g. Saturday trail runs). Anyone who belongs to or follows the box can join or ask to join. | Group. |
| Channel | Κανάλι | `community_channels` | A stream of posts inside a club: #ανακοινώσεις, #wod-σήμερα, #challenges, a class's channel, a season's channel. | Conversation (Μηνύματα). |
| Member group | Ομάδα μελών | `channel kind: member_group` | A channel members propose inside their box's club; has its own admins. | Open club (staff-made, its own bubble). |
| PT squad | Ομάδα του coach | `channel kind: pt_squad` | A coach's private channel with up to 30 of their own clients. Greek formerly «PT squad». (ADR-168) | Member group, class. |
| Class channel | Κανάλι τμήματος | `channel kind: class_slot` | The channel of one class on the schedule. Formerly «ομάδα τάξης», «Κανάλι μαθήματος». | Member group. |
| Personal training | Προσωπική προπόνηση | `pt_pack`, appointments | One-to-one sessions with a coach, sold as personal training packages («Πακέτο προσωπικών προπονήσεων»). "PT" is never written in Greek. | Class. |
| Online programming | Online προγραμματισμός | `online_coaching` (package module) | A package service where a coach sends personal training plans and, optionally, messages, check-ins, technique video reviews and a nutrition plan, all remotely. Formerly "Online coaching" / «Online καθοδήγηση»; the code key stays `online_coaching` because saved packages store it. | Personal training (in person), Coaching (the coach ↔ client relation). |
| Event | Εκδήλωση | `community_events` | A one-off or weekly happening with places, price and attendees. Run by a club or an organiser. | Class (on the schedule). |
| Class | Τμήμα | `class_slots` | A scheduled session on the box's timetable, booked with a subscription package. The code's "slot" is never shown: a class is never «slot», «θέση», «τάξη», «κλάση» or «κουλοχέρης». | Event, class type (Τύπος τμήματος). |
| Recurring class | Επαναλαμβανόμενο τμήμα | `class_series` | A class that repeats on a pattern (formerly "series"). The form's start time is "Class start time" / «Ώρα έναρξης τμήματος». | Season. |
| Trial class | Δοκιμαστικό τμήμα | `trials` | A newcomer's free class. Short form «Δοκιμαστικό». A trial period of a plan is «Δοκιμαστική περίοδος». | Guest. |
| Day WOD | WOD ημέρας | `day_workouts` | The WOD set for a whole date: every class (τμήμα) of that day, or only chosen class types (and, with branches, one branch), takes it unless the class has its own WOD. (ADR-230) | A class's own WOD (an override); «WOD σήμερα» (the club channel). |

### 4.5 Relations between people

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Follow / follower | Ακολουθώ / ακόλουθος | `community_follows` | One-way. Instant for public profiles (the default), a request for private ones. | |
| Buddies | Φιλαράκια | derived: mutual follows | Two people who follow each other. Can message each other anywhere. (ADR-193) | Check-in buddy. |
| Training partner | Συναθλητής **(proposed)** | `partners` context | A match between two members of the same club who both said yes, to train together («Κλείστε μαζί»). Opt-in per club. (ADR-169) | Partner business. Today the Greek UI says "Partners". |
| Check-in buddy | Φιλαράκι στήριξης | `buddy_links` | One or two people you pick to hear from you when you ask for support (cravings, motivation); can get your weekly summary. (ADR-160) | Buddies (mutual follow). |
| Coaching | Coaching | `coaching_relationships` | A coach and a client at one business. Decides what the coach sees and who can join their PT squad. | Follow. |
| My clients | Οι πελάτες μου | coach view | The coach's list of active coaching clients (Box › Πελάτες μου). | Members of the box. |
| PR sharing | Κοινοποίηση PR | `pr_sharing_grants` | A person lets a specific person see all their PRs. | Follow. |

### 4.6 Conversations (Μηνύματα)

| English | Ελληνικά | Code | What it is |
|---|---|---|---|
| Conversation | Συνομιλία | `person_conversations` | Two people, anywhere on Palee. |
| Message request | Αίτημα μηνύματος | `folder: requests` | A first message from someone you have no relation with. |
| Group chat | Ομαδική συνομιλία **(proposed name)** | `messaging_threads` box/class | The box's thread and each class's thread. Today they sit under the «Clubs» tab. There is no user-made group chat yet. |
| Coach chat | Συνομιλία με coach | thread with a coach / assignment | Chats about your training with your coach; the «Coach» tab. |
| Training partner chat | Συνομιλία συναθλητών | partner match thread | Opens when a training-partner match happens. |
| Check-in buddy chat | Συνομιλία στήριξης | buddy support thread | Opens when a check-in buddy answers a support request. |

### 4.6a Class booking rules (ADR-226)

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Time to answer a booking request | Χρόνος για απάντηση σε αίτηση κράτησης | `booking_timeout_minutes` | Without automatic confirmation, how long a request waits for staff before it is cancelled; «Χωρίς όριο» = until the class starts. | Bookings open; a booking deadline. |
| Bookings open | Άνοιγμα κρατήσεων | `booking_window_days` | The earliest a member can book, in days before the class. Bookings stay open until the start. | Time to answer a request. |
| Late cancellation | Καθυστερημένη ακύρωση | `default_cancellation_cutoff_minutes` | Cancelling later than this before the class still uses the visit. Entered as hours + minutes. | Cancelling a class (staff). |
| Automatic confirmation | Αυτόματη επιβεβαίωση κρατήσεων | `auto_approve` | A booking is confirmed at once instead of waiting for staff. | Booking request. |

### 4.7 Outside parties

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Partner business | Συνεργάτης | `perks.partner_name` | An outside shop or service that gives the box's clients a perk. Has no Palee account. (ADR-191) | Training partner. |
| Perk | Προσφορά συνεργάτη | `perks` | A discount or gift from a partner business, claimed in Πληρωμές › Προσφορές. | Promotion (the box's own discount). |
| Corporate client | Εταιρικός πελάτης | `finance_corporate_clients` | A company that pays memberships for its employees. | Client (a person). |
| Guest | Καλεσμένος | event `source: guest` | Someone a member brings to an event. | Trial visitor. |
| Trial visitor | Δοκιμαστικό | `trials` | A newcomer trying one class. | Guest, mock person. |
| Referral | Φέρε φίλο | `referrals` | A member invites a friend; rewards on trial or join. | Guest. |

### 4.8 Terms in other languages

"Coaching", "coach", box, WOD, PR, RX, scale, AMRAP, EMOM, For Time, Tabata and check-in stay untranslated where
gyms use them. Address is always informal singular (du, tu, tú, ты, εσύ). `apps/web/src/i18n/ontology-wording.test.ts`
fails on the banned words.

| Locale | Class | Recurring class | Class start time | Subscription package | Banned for a class |
|---|---|---|---|---|---|
| en | class | recurring class | Class start time | subscription package | slot, series |
| el | τμήμα | επαναλαμβανόμενο τμήμα | Ώρα έναρξης τμήματος | πακέτο συνδρομής | τάξη, κλάση, κουλοχέρης, δίκη (trial) |
| de | Kurs | wiederkehrender Kurs | Kursbeginn | Abo-Paket | Klasse, Slot, Steckplatz, Spielautomat |
| fr | cours | cours récurrent | Heure de début du cours | forfait d'abonnement | classe, emplacement, machine à sous |
| es | clase | clase recurrente | Hora de inicio de la clase | paquete de suscripción | ranura, tragaperras |
| it | lezione | lezione ricorrente | Ora di inizio della lezione | pacchetto di abbonamento | classe, slot |
| ru | занятие | повторяющееся занятие | Время начала занятия | абонементный пакет | класс, урок, слот |
| pt-PT | aula | aula recorrente | Hora de início da aula | pacote de subscrição | turma, classe, slot, ranhura |
| nl | les | terugkerende les | Begintijd van de les | abonnementspakket | klas, slot, sleuf, gokkast |
| bg | занятие | повтарящо се занятие | Начален час на занятието | абонаментен пакет | клас, слот, ротативка |
| ar | حصة | حصة متكررة | وقت بدء الحصة | باقة اشتراك | فصل، صف، فتحة، آلة القمار |
| he | שיעור | שיעור קבוע | שעת תחילת השיעור | חבילת מנוי | כיתה, משבצת, מכונת מזל |

pt-PT, nl, bg, ar and he got only these terms and the class fixes; their full rewrite is TD-206.

### 4.9 Goals and streaks

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Weekly goal | Εβδομαδιαίος στόχος | `training_goals` kind `weekly_workouts` | How many workouts make a person's week count. Theirs to set; their coach (or staff who coach every client) may set it, and the person is told. (ADR-229) | WOD goals (the muscles and qualities a workout trains). |
| Streak | Σερί | `user_stats.current_streak` | Days or weeks in a row of training. One streak only (ADR-194). | |
| Streak shield | Ασπίδα σερί | `gamification_settings.streak_shields` | Saves a streak in a week that missed the weekly goal. The box sets how many each client gets (0–5) and when they renew. (ADR-229) | |
| Shield renewal | Ανανέωση ασπίδων | `streak_shield_reset_day` | When shields are topped up: a day of the month for everyone, or each client's sign-up day. | |

### 4.10 Taking money at the desk (ADR-222, ADR-249)

| English | Ελληνικά | Code | What it is | Not to be confused with |
|---|---|---|---|---|
| Tap to Pay | Tap to Pay | `payment_intents.initiation = terminal`, `/admin/payments/terminal` | Staff take a contactless card on their own phone through the «Viva.com Terminal» app; Palee records it after Viva confirms it. The brand name stays in English in both languages. | Online payment (the payer pays on the provider's page). |
| Card (Tap to Pay) | Κάρτα (Tap to Pay) | payment method `card_terminal` | A card payment Palee confirmed with the provider; never chosen by hand. | Card at the terminal (`card_manual`): staff's word that a standalone card machine took it. |
| Card at the terminal | Κάρτα στο τερματικό | payment method `card_manual` | A card payment on the box's own card machine, recorded by staff. | Card (Tap to Pay). |
| Free sale | Ελεύθερη πώληση | purpose `free_sale` | Money for something with no invoice, package or order: a description and a category, for a member. | Shop order. |
| Walk-in | Επισκέπτης χωρίς λογαριασμό | `shop_orders.customer_name`, no `user_id` | Someone who pays at the desk without a profile in the business. Tap to Pay takes a walk-in's money for a shop order only. | Member, mock person, trial visitor. |

## 5. Name clashes found, and proposals

Each needs ANR's choice before the UI changes. The recommended option is first.

1. **"Partners" means three different things.**
   - Training partners (member ↔ member match), partner businesses (perks), and the Μηνύματα tab
     that holds both training-partner and check-in-buddy chats.
   - **Proposal:** training partner → EN "Training partner", EL «Συναθλητής»; partner business stays
     "Partner" / «Συνεργάτης» and appears only in perks screens; the inbox tab becomes
     "Training partners" / «Συναθλητές», and check-in buddy chats move to the «Άτομα» tab.
2. **"Buddies" and "Check-in buddy" sound like the same thing.**
   - **Proposal A (lighter):** keep both, but never write a bare "buddy" for the check-in kind; always the
     full name.
   - **Proposal B:** rename check-in buddy → "Support person" / «Άτομο στήριξης».
3. **The coach business has five names** (Personal coach, Independent coach, Solo coach,
   «Προσωπικός coach», «Ανεξάρτητος προπονητής»).
   - **Proposal:** "Independent coach" / «Ανεξάρτητος coach» everywhere.
4. **Box, gym and «Γυμναστήριο» are used for the same business.**
   - **Proposal:** "Box" in every member-facing screen, whatever the discipline (dance academies
     included); "Gym or box" only on the sign-up choice, where people pick their kind.
5. **Branch is «Κατάστημα» in staff screens and «Παράρτημα» in the shop**, and «Κατάστημα» is also
   the e-shop.
   - **Proposal:** Branch = «Παράρτημα»; Shop = «Κατάστημα».
6. **Coach vs «προπονητής» in Greek.**
   - **Proposal:** «coach» everywhere (the app already says Box › Coach, head coach).
7. **Followers in Greek** appear as «followers», «Όσοι με ακολουθούν» and «Ακολουθείς».
   - **Proposal:** noun «ακόλουθοι», verb «ακολουθώ».
8. **«Clubs» tab in Μηνύματα** lists the box's and classes' group chats, not clubs.
   - **Proposal:** rename the tab to "Box" / «Box», and call those threads "group chats".
9. **Athlete** is a role (gets personal programming), but every user trains, and box tags also say
   "Competitive athletes".
   - **Proposal:** keep the role, but show it as "Athlete (personal programming)" /
     «Αθλητής (προσωπικό πρόγραμμα)» wherever roles are picked.

## 6. Rules for new terms

- Add the term to §4 in both languages before it reaches a screen.
- Prefer a word the app already uses over a synonym; never reuse a word for a second thing.
- Code names stay English and may differ from UI names; the «Code» column links them.
