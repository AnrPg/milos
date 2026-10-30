// Everything Palee does, grouped the way the About page shows it. Titles and
// summaries are UI copy (SiteInfo namespace, all locales); the detail lines
// are the English reference for llms.txt, where answer engines read the
// specifics. Keep them to features that exist on main.

export type FeatureSection = {
  id: string;
  side: "social" | "business" | "both";
  titleKey: string;
  summaryKey: string;
  details: string[];
};

export const FEATURE_SECTIONS: FeatureSection[] = [
  {
    id: "social",
    side: "social",
    titleKey: "socialTitle",
    summaryKey: "socialSummary",
    details: [
      "Feed with a club bar; every post shows its origin (club and channel); scope toggle between My people (clubs and people you follow) and Around me",
      "Posts with up to 4 photos or video, text-only posts, and an optional workout attached from the journal",
      "Audience picker per post: a club channel, followers or public",
      "Clubs with channels: announcements, today's WOD with leaderboard, challenges, time-slot groups, seasons, PT squads, member-created groups and open clubs that non-members can join",
      "Follows and follow requests, profile with posts, shared PRs and clubs",
      "One search for clubs, people, boxes and independent coaches by name, forgiving accents, Latin spelling and typos",
      "Around me: nearby events, open clubs, gyms offering trials and public posts, as a list or a map, with radius, discipline, time, cost, level, language and audience filters and saved filter combinations",
      "Direct messages and threads, notifications and web push",
      "Message any box from its page; the box answers from one shared team inbox, with coaches brought in for training questions",
      "Moderation: report queue, block, auto-archive of inactive member groups",
    ],
  },
  {
    id: "partners",
    side: "social",
    titleKey: "partnersTitle",
    summaryKey: "partnersSummary",
    details: [
      "Training partners: one public deck for verified adults (18+) across Palee, opened from Around me; verified once by an active box or coach membership, or by two sponsors and a check by the Palee team",
      "Full-screen cards to swipe, mutual match only, then message and plan together with up to three suggestions (classes of a shared box, or events and trial classes near both)",
      "Filters by level, time, goal, discipline and distance between neighbourhoods (2, 5, 10 or 25 km, never live location); report to the Palee team, which also blocks; opt out at any time",
      "Check-in buddy: one or two trusted people who receive only what the user sends with \"I need support\", with quick replies",
      "Optional weekly counts-only summary; a coach summary only with permission",
    ],
  },
  {
    id: "events",
    side: "both",
    titleKey: "eventsTitle",
    summaryKey: "eventsSummary",
    details: [
      "Events from gyms, coaches, clubs, member groups and individual organisers: open WODs, bootcamps, runs, competitions and socials",
      "RSVP (\"I'm going\"), capacity, waitlist, guest passes, invitations and free or paid tickets",
      "Organise as yourself or as a business, with co-hosts that accept the invitation",
      "Organiser console with management, finances and analytics tabs",
      "Event cards in club feeds, on the public gym page and in Around me",
      "Times shown in the event's own time zone with a \"your time\" badge for travellers",
    ],
  },
  {
    id: "box",
    side: "social",
    titleKey: "boxTitle",
    summaryKey: "boxSummary",
    details: [
      "Box tab: today's workout card from every provider (gym classes and personal coaches) with source labels and a provider switcher",
      "Class schedule with filters (location, class type, coach, time, only with free spots, only covered by my package), waitlist, open-gym check-in and calendar (ICS) export",
      "Appointments, video library and a coach area with programs, form reviews and nutrition",
      "Check-in with a rotating door QR code (screenshots don't work), Apple and Google Wallet passes, a personal QR, NFC door tags and a geofenced reminder in the native app",
      "Packages, entitlements, seasons, corporate enrollment, invoices and refund receipts per provider",
    ],
  },
  {
    id: "training",
    side: "social",
    titleKey: "trainingTitle",
    summaryKey: "trainingSummary",
    details: [
      "Workout execution screen with a step-synchronised timer, auto-progressing steps, modifications and per-exercise notes",
      "Structured and free-text WODs with sections and per-section scoring; structured WODs run set-wise supersets, per-round values, interruptions and heart-rate rest",
      "WOD goals: target muscle groups, fitness qualities and stimulus, then \"what did you feel\" after the workout",
      "Injury warnings with acknowledgement before risky movements",
      "Quick logging of score, RPE and notes without the timer; voice logging that turns speech into a draft entry to confirm",
      "Offline check-offs saved on the device and synced later",
      "Class timer display for the gym's screen, controlled by the coach",
      "Optional AI scaling suggestions that a coach approves before members see them (off by default)",
    ],
  },
  {
    id: "journal",
    side: "social",
    titleKey: "journalTitle",
    summaryKey: "journalSummary",
    details: [
      "One journal across all gyms and coaches: workouts, PRs, measurements, wellbeing, cravings, injuries, technique videos, ratings and notes",
      "Visibility ladder on every entry: only me, my coach can see, ask for a reply, rating, or post",
      "Vault of completed workouts with dated results, trends and repeat",
      "Pantheon of personal records with optional sharing grants",
      "Filters by entry type, visibility, date, source and text search; export",
    ],
  },
  {
    id: "body",
    side: "social",
    titleKey: "bodyTitle",
    summaryKey: "bodySummary",
    details: [
      "Body snapshots: weight, body-fat %, circumferences and optional front, side and back photos",
      "Camera ghost outline of the previous photo for the same pose; compare slider or side by side; charts per metric",
      "Photos always private unless explicitly shared with the coach, with a second confirmation and optional blur",
      "Wellbeing today: water, sleep, meals in or out of plan, mood, energy and stress",
      "Craving log with intensity, trigger and outcome, linked to the check-in buddy",
      "Health-safe defaults: weight can be shown as a trend only, journal sections can be turned off, correlations shown as indicators, never medical advice",
    ],
  },
  {
    id: "progress",
    side: "social",
    titleKey: "progressTitle",
    summaryKey: "progressSummary",
    details: [
      "Consistency heatmap and streaks, perseverance (adherence to programmed work), strength (estimated 1RM), benchmarks and retest reminders",
      "Volume by modality, muscle coverage with push/pull and quad/hamstring balance, radar of the ten general physical skills",
      "Training load (session RPE, acute:chronic ratio as an indicator)",
      "Insights such as sleep versus performance and best time of day, only after enough data",
      "3D anatomy atlas: region, muscle group and muscle head, with the athlete's own sets, heat-map mode and exercises from the gym's library",
    ],
  },
  {
    id: "business",
    side: "business",
    titleKey: "businessTitle",
    summaryKey: "businessSummary",
    details: [
      "Business console for gyms, studios, boxes and martial-arts clubs",
      "Class schedule, recurring series and appointment slots; check-in desk with door display mode",
      "Workout library (WODs vault) with a workout assistant, sections and goals",
      "Structured WOD editor next to free text: a wizard per section (flow, time, exercises, score) with six flows (sets, For Time, AMRAP, EMOM, intervals, rest), set structures (superset, complex, cluster, drop set, rest-pause), interruptions and heart-rate rest, presets such as Tabata, Death by and EDT, values per set or per round with ranges, decimals and progressions, optional tempo, RPE, RIR, pace, heart-rate zone and per-side, fully keyboard-operable",
      "Seasonal challenges and leaderboards, community moderation and announcements, content and reviews",
      "Inventory and cleaning log",
      "Reports: overview, finance, training, coaching, engagement, health and marketing",
      "Demo mode: a new business tries everything with sample data before activation",
      "Interactive walkthroughs over the real screens for the shop, event organising and offers (campaigns, coupons, partner perks, referrals), with a demo-data fill for new businesses",
    ],
  },
  {
    id: "coaching",
    side: "business",
    titleKey: "coachingTitle",
    summaryKey: "coachingSummary",
    details: [
      "Coaching assignments and programs that athletes can accept, reschedule or request",
      "Reply queue for athlete questions and a form-review queue for technique videos",
      "Nutrition plans with macros, staff-only coach notes (read-audited), wellbeing summaries with consent",
      "PT squads: invite-only channels for a coach and their clients",
      "Solo-coach tier: independent trainers get a lighter console, session packages, a team club and open bootcamps",
    ],
  },
  {
    id: "finance",
    side: "business",
    titleKey: "financeTitle",
    summaryKey: "financeSummary",
    details: [
      "Package catalog, member packages and entitlements, seasons (for example 12-week race prep) with their own club channel",
      "Promotions, member billing, invoices and refund receipts",
      "Corporate clients and corporate invoices",
      "Reconciliation records and accounting exports with a checksummed manifest",
    ],
  },
  {
    id: "growth",
    side: "business",
    titleKey: "growthTitle",
    summaryKey: "growthSummary",
    details: [
      "Public gym page: about, photos, disciplines, coaches, locations, hours, read-only schedule, events and public posts",
      "Owner-controlled trial policy and slots, trial requests queue and conversion tracking; the check-in door offers a trial to non-members",
      "Member referrals with a personal link and QR, automatic attribution (sign-up, trial, paid) and rewards approved by the owner",
      "No credits, no discount marketplace: the owner sets prices and the client relationship stays with the gym",
    ],
  },
  {
    id: "branches",
    side: "business",
    titleKey: "branchesTitle",
    summaryKey: "branchesSummary",
    details: [
      "Staff roles and permissions (owner, branch manager, coach, front desk, cleaning and more), with invitations that carry roles and branches",
      "Branch filter on finance, coaching and statistics for staff who see several branches",
      "\"Applies to\" chips create a class, series or appointment slot per branch, or one package, promotion or coaching assignment for several branches",
      "Each gym uses its own time zone; times are stored in UTC",
    ],
  },
  {
    id: "devices",
    side: "both",
    titleKey: "devicesTitle",
    summaryKey: "devicesSummary",
    details: [
      "Installable progressive web app with an offline outbox",
      "Native iOS and Android builds with push notifications, deep links, home-screen widgets, NFC and geofencing",
      "Garmin, Apple Health and Health Connect import with de-duplication",
      "Calendar (ICS) feeds and Apple/Google Wallet passes",
    ],
  },
  {
    id: "privacy",
    side: "both",
    titleKey: "privacyTitle",
    summaryKey: "privacySummary",
    details: [
      "No ads and no tracking for advertising; notes, body data, photos and cravings private by default",
      "Injuries are the one exception: coaches always see them, for safety",
      "Report and block everywhere people meet; partner matching only with mutual consent",
      "Tenant data export and retention for gyms; journal export for athletes",
      "Twelve languages: English, Greek, Arabic, Russian, German, Spanish, Portuguese, Hebrew, Italian, Bulgarian, Dutch and French, with right-to-left layouts",
      "Light and dark themes",
    ],
  },
];
