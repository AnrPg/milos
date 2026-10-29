# Architecture Decision Records

ADRs document significant architectural decisions for this project.
Every non-trivial decision, especially decisions that constrain future work,
must have an ADR. See `template.md` for the format.

| ADR | Title | Status |
|---|---|---|
| ADR-001 | Project scaffold and monorepo structure | Accepted |
| ADR-002 | Authentication strategy | Accepted |
| ADR-003 | Auth refresh rotation and identity persistence adapters | Accepted |
| ADR-004 | Phase 0 and 1 production hardening | Accepted |
| ADR-005 | Workout materialization and admin-managed scale levels | Accepted |
| ADR-006 | Workout draft canvas authoring flow | Accepted |
| ADR-007 | Scheduling booking approval and timeout flow | Accepted |
| ADR-008 | Assigned workouts athlete delivery | Accepted |
| ADR-009 | Workout execution mode | Accepted |
| ADR-010 | Notification delivery and Web Push | Accepted |
| ADR-011 | Gamification landing read model | Accepted |
| ADR-012 | Execution score snapshots and authoring audit timestamps | Accepted |
| ADR-013 | Phase 8 UX improvements and production fixes | Accepted |
| ADR-014 | User-scoped realtime sync for landing and assigned workouts | Accepted |
| ADR-015 | Phase 8 finance, analytics, wellbeing, and feedback foundations | Accepted |
| ADR-016 | Finance credit ledger and entitlements | Accepted |
| ADR-017 | Finance invoices, renewals, and entitlements | Accepted |
| ADR-018 | Finance and Coaching read model hardening | Accepted |
| ADR-019 | Finance refunds and allocation reversals | Accepted |
| ADR-020 | Referral reward and coaching refresh hardening | Accepted |
| ADR-021 | Finance net accounting projections | Accepted |
| ADR-022 | Phase 8 lifecycle policy contract hardening | Accepted |
| ADR-023 | Dynamic gamification help copy | Accepted |
| ADR-024 | is_team_workout field and realtime sync infrastructure fix | Accepted |
| ADR-025 | Admin search, communication, attendance, and calendar export foundations | Accepted |
| ADR-026 | Financial member drill-down contract | Accepted |
| ADR-027 | Coaching athlete drill-down contract | Accepted |
| ADR-028 | Admin drill-down cross-surface alignment | Accepted |
| ADR-029 | Execution, booking, and challenge integrity | Accepted |
| ADR-030 | Athlete assignment and command integrity | Accepted |
| ADR-031 | Authenticated cache, workout revisions, and role transitions | Accepted |
| ADR-032 | Side effect, attendance, search, and notification lifecycle hardening | Accepted |
| ADR-033 | Global UI theme palette | Accepted |
| ADR-034 | Finance invoice reference format | Accepted |
| ADR-035 | Admin information architecture and user profiles | Accepted |
| ADR-036 | Health check SSL exemption | Accepted |
| ADR-037 | Configurable class type lifecycle | Accepted |
| ADR-038 | Transient page heroes and per-device push choice | Accepted |
| ADR-039 | Embedded workout authoring | Accepted |
| ADR-040 | Package entitlements and allowance ledger | Accepted |
| ADR-041 | Package retirement reconciliation | Accepted |
| ADR-042 | Security, integrity, and offline reconciliation | Accepted |
| ADR-043 | Compile-time hexagonal boundary enforcement | Accepted |
| ADR-044 | Verifiable delivery, observability, and web quality gates | Accepted |
| ADR-045 | Hybrid localization and RTL foundation | Accepted |
| ADR-046 | Workout hard deletion across dependent contexts (historical renumbering) | Superseded in part by ADR-029 |
| ADR-047 | Frontend catalog and RTL migration | Accepted |
| ADR-048 | Semantic localization at system boundaries | Accepted |
| ADR-049 | Admin-managed browser push configuration | Accepted |
| ADR-050 | Structured training log modification patches | Accepted |
| ADR-051 | Separate notifications and messages presentation | Accepted |
| ADR-052 | Structured PR results and supporting metrics | Accepted |
| ADR-053 | Display usernames and device push controls | Accepted |
| ADR-054 | Code-gated admin registration | Superseded by ADR-057 for tenant onboarding |
| ADR-055 | Organization tenancy and membership-scoped identity | Accepted |
| ADR-056 | Shared-schema tenant isolation with PostgreSQL RLS | Accepted |
| ADR-057 | Opaque one-time tenant invitations | Accepted |
| ADR-058 | Tenant resolution and request context | Accepted |
| ADR-059 | Tenant propagation beyond PostgreSQL | Accepted |
| ADR-060 | Staged legacy-tenant backfill and enforcement rollout | Accepted |
| ADR-061 | Semantic notifications and canonical deep links | Accepted |
| ADR-062 | Entitlement guidance and notification consolidation | Accepted |
| ADR-063 | Browser-safe avatar editing and dossier navigation | Accepted |
| ADR-064 | Shared collapsible home history | Accepted |
| ADR-065 | Private document export and system sharing | Accepted |
| ADR-066 | Home controls and avatar editor hardening | Accepted |
| ADR-067 | Durable offline command delivery | Accepted |
| ADR-068 | Structured workout set composition | Accepted |
| ADR-069 | Canonical workout DSL and assisted authoring | Accepted |
| ADR-070 | Rich canonical workout authoring metadata | Accepted |
| ADR-071 | Library organization and scoped programming | Accepted |
| ADR-072 | Document export rendering hardening | Accepted |
| ADR-073 | Recurring class series and receipt mode | Accepted |
| ADR-074 | Admin finance and user profile usability | Accepted |
| ADR-075 | Workout presentation and inline admin editing | Accepted |
| ADR-076 | Package-associated receipts | Accepted |
| ADR-077 | Free-text exercises and continuous DSL completion | Accepted |
| ADR-078 | Free-text workout authoring | Accepted |
| ADR-079 | Workout delete removes recurring class series | Accepted |
| ADR-080 | Workoutless recurring class series | Accepted |
| ADR-081 | Subtle finance payment rollback | Accepted |
| ADR-082 | Free-text execution modification notes | Accepted |
| ADR-083 | Platform provisioning and tenant lifecycle | Accepted |
| ADR-084 | Finance correction and soft-delete policy | Accepted |
| ADR-085 | Tenant-scoped coaching projections | Accepted |
| ADR-086 | Palee product shell and tenant branding | Accepted |
| ADR-087 | Platform owner tenant entry and permanent organization deletion | Accepted |
| ADR-088 | Platform tenant access management | Accepted |
| ADR-089 | Rename platform owner to vendor | Accepted |
| ADR-090 | Cross-layer quality gates and booking timeouts | Accepted |
| ADR-091 | Runtime tenant context must fail closed | Accepted |
| ADR-092 | Initial tenant admin invitation | Accepted |
| ADR-093 | Tenant delete purges eligible client accounts | Accepted |
| ADR-094 | Temporary clean slate production purge | Accepted |
| ADR-095 | Align account role with membership | Accepted |
| ADR-096 | Package types and entitlement catalog v2 | Accepted |
| ADR-097 | Package Phase B: booking rules, perks and facility | Accepted |
| ADR-098 | Package Phase C: new services and payment models | Accepted |
| ADR-099 | Role sets and capability authorization | Accepted |
| ADR-100 | Coach client scope and head coaches | Accepted |
| ADR-101 | Private coach notes and their access log | Accepted |
| ADR-102 | Front desk, accountant and janitor roles; housekeeping log | Accepted |
| ADR-103 | Role-aware navigation on today's UI | Accepted |
| ADR-104 | Gym inventory: machines and consumables | Accepted |
| ADR-105 | AI-assisted free-text workout authoring | Accepted |
| ADR-106 | Client invitations and public join link | Accepted |
| ADR-107 | First-run onboarding checklist and tours | Accepted |
| ADR-108 | Static page headers and client-side users directory | Accepted |
| ADR-109 | Structured-first workouts and workout assistant hardening | Accepted |
| ADR-110 | Canonical section format schemas and structure-first parsing | Accepted |
| ADR-111 | Reasoning-first workout assistant | Accepted |
| ADR-112 | Subscription expiry reminders and grace slack | Accepted |
| ADR-113 | Training log on profiles | Accepted |
| ADR-114 | Tenant-scoped admin fanout replaces global admin lookups | Accepted |
| ADR-115 | Dialyzer baseline paid down to zero | Accepted |
| ADR-116 | Observability dashboards and alerting | Accepted |
| ADR-117 | Reviewed tenant export and purge | Accepted |
| ADR-118 | Standalone training-log entries | Accepted |
| ADR-119 | Controller tests run under the RLS-enforcing runtime role | Accepted |
| ADR-120 | Offline outbox failure controls and command adapters | Accepted |
| ADR-121 | Tenant logo upload | Accepted |
| ADR-122 | Organization name and slug editing | Accepted |
| ADR-123 | Comprehensive analytics instrumentation | Accepted |
| ADR-127 | Web dependency security refresh and patched OpenAPI generator chain | Accepted |
| ADR-124 | Injury-aware workout safety warnings | Accepted |
| ADR-125 | Personalized member programming | Accepted |
| ADR-126 | Refund receipts, provider reconciliation and accounting exports | Accepted |
| ADR-128 | Tenant-owned scale levels | Accepted |
| ADR-129 | PR visibility for gym coaches and explicit sharing grants | Accepted |
| ADR-130 | Injury warnings on the ready screen, scaled variations and drop-off facts | Accepted |
| ADR-131 | Background and system paths under RLS | Accepted |
| ADR-132 | Coach PR dossier, legacy PR provenance backfill and grantee lookup | Accepted |
| ADR-133 | Atomic organization provisioning and tenant-scoped workout reads | Accepted |
| ADR-134 | BEAM literal area root cause and deterministic OpenAPI export | Accepted |
| ADR-135 | One staff dashboard for every role | Accepted |
| ADR-136 | Self-organising workout library and workout icons | Accepted |
| ADR-137 | Member app shell, four tabs and route moves | Accepted |
| ADR-138 | Community context: clubs, channels and posts | Accepted |
| ADR-139 | Journal visibility ladder, notes and check-ins | Accepted (§8 check-ins superseded by ADR-140) |
| ADR-140 | Journal text ontology: notes, comments, instructions, messages | Accepted |
| ADR-141 | Places, location pins and geocoding | Accepted |
| ADR-142 | The gym's public profile, drafts and canonical tags | Accepted |
| ADR-143 | Open clubs, member groups and moderation | Accepted |
| ADR-144 | Trials (and later events) | Accepted |
| ADR-148 | Media uploads | Accepted |
| ADR-151 | Filters and saved filters | Accepted |
| ADR-152 | AI usage metering per call, operation and gym | Accepted |
| ADR-153 | Club events, attendees and guest passes | Accepted |
| ADR-154 | Γύρω μου: nearby discovery, home areas and saved-filter alerts | Accepted |
| ADR-155 | QR check-in, the printed poster, static member codes and Wallet | Accepted |
| ADR-156 | Member referrals («Φέρε φίλο») | Accepted |
| ADR-157 | Photos and video in posts | Accepted |
| ADR-158 | Body snapshots, private photos and coach access | Accepted |
| ADR-159 | Wellness (water, sleep, meals) and cravings | Accepted |
| ADR-160 | Buddy για στήριξη and the coach's weekly wellness summary | Accepted |
| ADR-161 | Garmin: OAuth, push ingest, matching and the devices row | Accepted |
| ADR-162 | One journal across providers and the Box ▾ provider switch | Accepted |
| ADR-163 | WOD goals, «τι ένιωσες» feedback and the anatomy taxonomy | Accepted |
| ADR-164 | Anatomy atlas, coverage weighting and the gym's exercises per muscle | Accepted |
| ADR-165 | Muscle coverage, the qualities radar and training load in Πρόοδος | Accepted |
| ADR-166 | Insights in Πρόοδος: rules, nightly job, sufficiency and dismissal | Accepted |
| ADR-167 | Seasons: fixed-length programmes a gym sells | Accepted |
| ADR-168 | PT squads | Accepted |
| ADR-169 | Partners: training partners within a club, matches, «Κλείστε μαζί» and blocking | Accepted |
| ADR-170 | Solo-coach tier, platform plans and the coach-centred Box | Accepted |
| ADR-171 | Native wrapper: Capacitor store apps, app links and native push | Accepted |
| ADR-172 | Phone health data: Apple Health and Health Connect | Accepted |
| ADR-173 | Widgets, the arrival reminder (geofence) and NFC door tags | Accepted |
| ADR-174 | AI scaling suggestions with mandatory coach approval | Accepted |
| ADR-175 | Voice logging: record, transcribe, parsed draft, confirm to save | Accepted |
| ADR-176 | Classes without a WOD (drafts, missing-WOD alerts) and the gym's time zone | Accepted |
| ADR-177 | One dialog shell, one popover primitive and a z-index scale | Accepted |
| ADR-179 | One canonical clock (UTC), the organiser's zone and the viewer's "your time" | Accepted |
| ADR-180 | Workouts in text sections, the WOD-assistant switch and per-section scoring | Accepted |
| ADR-181 | Tabbed WOD editor and in-place, colour-coded assistant suggestions | Accepted |
| ADR-182 | Themed dropdowns and date and time pickers instead of native controls | Accepted |
| ADR-183 | The member first-run and account interests | Accepted |
| ADR-184 | Business accounts: demo mode, the go-live gate and activation by the Palee team | Accepted |
| ADR-185 | Event organisers («Διοργάνωση ως»), co-hosting and the organiser console | Accepted |
| ADR-186 | Branch-scoped staff and the branch manager | Accepted |
| ADR-187 | Logins with up to three profiles, @handle + display name, and mail-free password recovery | Accepted |
| ADR-188 | Worldwide area and address search: GeoNames towns, our own Photon, the public Photon | Accepted |
| ADR-190 | E-shop: catalog, inventory, orders and revenue lineage | Accepted |
| ADR-191 | Partner perks: redemption methods, an open policy model and versioned terms | Accepted |
| ADR-192 | Shop analytics, revenue by stream and revenue lineage reporting | Accepted |
| ADR-195 | One red error notice everywhere, and a language picker on the signed-out pages | Accepted |
| ADR-196 | One inbox, the fixed Εγώ list, and a home for every sharing choice | Accepted |
| ADR-193 | In-app walkthroughs: one guide engine over real screens | Accepted |
| ADR-197 | One filter pattern on every list; feed types, Around level, partner disciplines and distance | Accepted |
| ADR-198 | Box › «Πελάτες μου»: the coach's home in the member app | Accepted |
| ADR-199 | Notification preferences per category and channel, checked at the bell and push chokepoints | Accepted |
| ADR-200 | Series edits, pause / cancel / delete reach this class, all upcoming classes or a date range, every nth; duplicate a class | Accepted |
| ADR-201 | WOD variation for several people at once: each programmed as if alone, results per person | Accepted |
| ADR-202 | Spaces: floor plans, unavailability, class spaces, cleaning schedule and machine placement | Accepted |
| ADR-203 | Transactional email outbox: templates, single-use link tokens, budgets, suppression | Accepted |
| ADR-204 | An existing profile accepts an owner or staff invitation; an email with an account is told to use its password or sign in | Accepted |
| ADR-205 | Verified email gates: company seats by email domain, business activation links emailed to a verified address | Accepted |
| ADR-206 | Password reset by email to a verified address (1 h link, peek then consume with the password change), handlers as fallback | Accepted |
| ADR-207 | Email change confirmed by a link to the new address, revert link to the old one, 7-day lock | Accepted |
| ADR-208 | Security notices by email, new-sign-in alert and the "sign out everywhere" link | Accepted |
| ADR-209 | Client and staff invitations sent by email: delivery status, resend, bulk caps, inbox binding | Accepted |
| ADR-210 | Owner invitation email on the outbox; share links by email | Accepted |
| ADR-211 | Sign-up that does not reveal accounts; self-service deletion with password, emailed link and a 7-day undo | Accepted |
| ADR-212 | Email deliverability: Brevo webhook, suppression state, one-click unsubscribe, budget and key-expiry alarms, retention | Accepted |
| ADR-213 | Email verification at sign-up: emailed link, resend, banner, `email_verified` | Accepted |
| ADR-214 | Form errors live in the form, on the field, in plain words; class starts never proposed in the past | Accepted |
| ADR-215 | Client data freshness by kind, and one shared realtime connection | Accepted |
| ADR-216 | One join link per client role: box-member link and athlete link (with a secret key), each on or off | Accepted |
| ADR-217 | People are shown by their roles in the business, never `users.role`; only clients have a finance profile | Accepted |
| ADR-218 | Web Push keys belong to the platform console, not to a gym's settings (moves ADR-049's editor) | Accepted |
| ADR-219 | Role hierarchy enforced downwards (vendor › owner › admin › staff › clients); self-added roles below one's top role | Accepted |
| ADR-221 | Find a box or coach by name; publishing the public page is a setup step | Accepted |
| ADR-222 | Record money received at the desk; the billing setup picks the receipt, paid invoice or invoice it settles | Accepted |
| ADR-223 | A new WOD written in context comes back to its form and is assigned to it; programming copies keep how they were written | Accepted |
| ADR-224 | A workout's `body` has its own shape per way of writing (free text, text sections, structured) | Accepted |
| ADR-225 | A WOD is assigned to a person (athlete or member) only when their package includes online programming or personal training | Accepted |
| ADR-226 | Class booking rules explained; approval wait may have no limit; late-cancellation cutoff in minutes (hours + minutes input) | Accepted |
| ADR-229 | The weekly workout goal is personal (the person, their coach, full-scope staff set it); the box sets only streak shields and their renewal | Accepted |
| ADR-230 | Day WODs: one WOD for a whole day, inherited by its classes (all or chosen class types), overridable per class | Accepted |
| ADR-231 | The profile's «Πολυμέσα» grid: photos and videos from posts, same visibility as posts | Accepted |
| ADR-232 | Staff book or move a member into a class: one transaction, no late charge, server-listed choices | Accepted |
| ADR-240 | Fiscal context, business legal identity and country profiles (GR, CY, DE, AT, CH, LI, LU, FR, BE, MC, GB, US) | Accepted |
| ADR-241 | Immutable fiscal documents, gapless series, VAT by rate group, credit notes only | Accepted |
| ADR-242 | Inalterable fiscal journal: hash chain, Ed25519 signatures, period closings, audit archive | Accepted |
| ADR-243 | Reporting fiscal documents to myDATA: outbox, sandbox and AADE gateways, document mapping | Accepted |
| ADR-244 | Tax categories on packages, products and variants; stable sale lines for `Fiscal.issue`; US sales tax port with a manual rate table | Accepted |
| ADR-245 | Country document templates (PDF/HTML, Swiss QR-bill, myDATA mentions) and accounting exports (DATEV, Xero, QuickBooks, Sage, bexio, CSV, JSON) | Accepted |
| ADR-246 | Online payments through the business's own provider account (Viva, Stripe, sandbox), webhooks as hints | Accepted |
| ADR-247 | Saved cards, recurring charges within the payer's consent, autopay and dunning | Accepted |
| ADR-248 | Selling packages and shop orders online, booking after payment, 14-day withdrawal | Accepted |
| ADR-249 | Tap to Pay at the desk through the Viva.com Terminal app: signed app-to-app request, result confirmed with Viva, `card_terminal` money with its document | Accepted |
| ADR-250 | Peppol e-invoicing: UBL 2.1 / BIS Billing 3.0, outbox with uncertain never resent, access point port (sandbox, fiskaly E-INVOICE since 2026-10-29; Storecove retired) | Accepted |
| ADR-251 | Till security devices: cloud TSE (DE), RKSV (AT) and SIGN FR (FR, ADR-266) through fiskaly, signatures on a side table, outages recorded; invoices paid at the till signed too (update 2026-10-29) | Accepted |
| ADR-252 | Documents and simple electronic signatures (evidence, PDF certificate), health certificates, booking gate | Accepted |
| ADR-253 | Box screen: TV paired with a code, display token, today's classes/WODs/leaderboards, automatic focus and staff override; the class's coach pins their own class (update 2026-10-29) | Accepted |
| ADR-254 | Importing clients from a CSV file: Imports context, dry run, idempotent apply, held profiles, undo | Accepted |
| ADR-255 | Setup recipes per box type and the settings catalog («Προχωρημένα») | Accepted |
| ADR-256 | Store apps: physical services paid through the box's provider in the in-app browser, digital-only packages and Plan (Palee) not sold in the apps, /pay/return app link | Accepted |
| ADR-260 | What members pay online (per-purpose switches), failed saved-card charges: member and staff notices, Εκκρεμότητες tab | Accepted |
| ADR-261 | One-button connection of the business's Stripe (Connect OAuth) or Viva (ISV) account; platform credentials, signed state, disconnect | Accepted |
| ADR-262 | Every recorded payment (desk or online) issues its fiscal receipt once the fiscal identity is complete; part payments split per tax group; idempotent per payment | Accepted |
| ADR-263 | Member payment screens: buy a subscription package, pay an invoice, saved cards and autopay, withdrawal, /pay/return with the sandbox page, the box's sales page; API adds provider, services, autopay at checkout, dated visits without withdrawal | Accepted |
| ADR-264 | Tap to Pay for walk-ins' free sales (memberless Finance stream sale with its receipt, idempotent per intent); tips (staff's, not revenue) and card surcharges (revenue on the sale's receipt) Viva confirms on top of the amount | Accepted |
| ADR-265 | Credit note reason (immutable, hashed, printed, UBL note) and refund to the card that issues the note; «Αποστολή με email» of a document PDF through the outbox (attachments); «Συμπλήρωση από το ΑΦΜ» from AADE RgWsPublic2 with the business's own encrypted credentials | Accepted |
| ADR-266 | French till receipts signed through fiskaly SIGN FR next to Palee's own journal (ADR-241/242); fiskaly must confirm certification coverage in writing; Monaco not covered | Accepted |
| ADR-267 | Draft `/privacy` and `/terms` pages (12 locales, sub-processors from the code); minimum age 16 as an explicit confirmation enforced in the API (no date of birth); «Λήψη των δεδομένων μου»: one ZIP of the person's own data across contexts, built by a job in the person's own sessions, short-lived links, email notice, one a day | Accepted |
| ADR-273 | Fiscal «Συνδέσεις» in Στοιχεία τιμολόγησης: «Δοκιμή σύνδεσης» behind every fiscal port (on save, on demand, about every 3 months, sooner after failures), stable error codes instead of provider text, owner notified when a connection becomes invalid; per-box `managed_by` lets the Palee team fill a box's connections from the vendor console, audited without secrets | Accepted |
| ADR-300 | Operation registry: one spec per use case generates REST, MCP and LLM tools; previewable commands, problem details, idempotency keys, ETags (v4) | Proposed |
| ADR-301 | AI agents as delegated principals: rights intersected on every call, durable runs, Rule-of-Two policy, approvals, one LLM provider port, multi-agent via delegation (v4) | Proposed |
