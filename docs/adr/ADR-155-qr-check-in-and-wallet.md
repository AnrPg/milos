# ADR-155: QR check-in, the printed poster, static member codes and Wallet
Date: 2026-10-20
Status: Accepted

## Context
Plan §5a board 10 (P2-M7) and vision §7.5 call for check-in by QR. This
ADR covers what the plan calls "ADR-145 QR check-in and Wallet"; ADRs take
the next free number when accepted, so it is recorded as ADR-155.

A box shows a rotating QR at the door. A signed-in person scans it with the
phone camera and is checked in to the class they booked, or to open gym, or
is offered what the box has. At the desk, staff scan a member's personal QR.
Members can keep a card in Apple or Google Wallet.

Before this, check-in was in-app only:
- class self check-in (TD-105)
- open gym `CheckInOpenGym`
- desk search

None of them recorded how a check-in happened.

ANR's picks on board 10 (Q1 A, Q2 A, Q3 A, Q4 A with desk auto mode, Q6 A)
add three things:
- a printed poster for boxes without a screen (Q1 extra);
- a staff notification when a non-member scans (Q3 note);
- the owner's choice of a rotating or a static personal code, with Wallet
  only for static codes (Q5 note).

## Decision
1. **Door QR without a table.**
   - A code is `HMAC-SHA256(key, "door:v1" ‖ location ‖ rotation ‖ window)`,
     truncated to 96 bits and base64url encoded (16 characters).
   - `window` is the 30-second period since the epoch; the owner can choose
     15 or 60 instead.
   - A code is accepted in its own window and one window either side.
   - `key` is derived from `facility_locations.door_secret` (32 random
     bytes) and the application secret, through `Ports.KeyDerivation`
     (PBKDF2 of `secret_key_base` via `Plug.Crypto`, then HMAC). A database
     dump alone cannot forge codes.
   - «Νέος κωδικός πόρτας» (`POST …/check-in/door/:location/rotate`)
     replaces the seed, which kills every code shown so far.
2. **The door display.** `GET /api/org/:slug/admin/check-in/door/:location`
   returns:
   - the current `code` and the deep link `/c/<location>/<code>`;
   - `seconds_until_rotation`;
   - an offline batch, `codes[]`, each with `shows_from` and `valid_until`.
     The batch holds `max(120 / rotation, 2)` windows, so it covers a short
     network drop, and a leaked batch is useless about two minutes later;
   - the next class here with a spot;
   - check-ins of the last 30 minutes, first names only;
   - the realtime topic `check_in:<organization>`, a staff-only channel
     (`check_in` capability) carrying `checked_in`, `check_in_undone` and
     `visitor_scanned`.
3. **The door scan is one pure decision.** `POST /api/check-in/scan` with
   `location_id` + `code` resolves the box through a narrow SECURITY DEFINER
   lookup, `milos_door_location`, which returns only what the door itself
   shows. It then gathers facts and asks `ResolveScan.decide/4`, in this
   order:
   1. A booking at this location whose class starts within the owner's
      window (default 30′ before to 15′ after; edges inclusive) is checked
      in. With several bookings in the window, the answer is `choose` with a
      `scan_token` (Phoenix.Token, 180 s, bound to the person and the door),
      and the client posts again with the `booking_id`.
   2. Otherwise a member gets open gym, if the package covers it or the
      owner doesn't require one.
   3. Otherwise `nothing`: the classes starting in the next 3 hours here
      with a spot («Κλείσε θέση») and the member's next booking.
   4. Otherwise the person is a visitor.

   Scanning again is a no-op (`already_checked_in`). A check-in comes with:
   - an `undo_token` good for 60 s. `DELETE /api/check-in/scan/:token`
     deletes the attendance or the open-gym check-in and releases its
     entitlement reservation;
   - `package`: status, name, expiry, frozen-until, and visits left.

   Open gym from a scan reserves the visit and finalizes it in
   `FinalizeScanCheckInJob` after the undo minute. The open-gym idempotency
   key is now per check-in, so checking in again after an undo works.
4. **Visitors.** A non-member gets:
   - the box;
   - `membership` (`none` | `former`);
   - the follow state;
   - when the owner's `visitor_trial_offer` is on, the trial classes of
     today and tomorrow at this location with their trial seats
     (`Trials.offer`, published boxes only).

   The scan is stored in `facility_visitor_scans`; the desk sees it as
   «Επισκέπτης» via `GET …/check-in/visitors` and the realtime line.
   Staff with `check_in` also get a `check_in_visitor` notification
   (12 locales) with the person, the box, the time and whether trials are
   open, linking to the visitor at the desk. It is sent at most once an
   hour per person and box: the previous hour's visitor scans are checked,
   and the dedupe key carries the hour.
5. **The printed poster** (board 10 Q1 extra), for boxes without a screen.
   - Each location has a static code, `HMAC(key, "poster:v1" ‖ location)`,
     where `key` is derived from `facility_locations.poster_secret`. The
     deep link is `/c/<location>/p/<code>`.
   - The owner turns it on or off per location
     (`PUT …/door/:location/poster`) and can rotate it.
   - A static code is weaker proof of presence, so a poster scan
     (`poster_code`) **only** checks in a booking already in its window.
     `ResolveScan` with `source: :poster` returns
     `{:poster_no_booking, :member | :visitor}`: never open gym, never
     suggestions, and for a visitor nothing beyond «not a member». Visitor
     scans are still recorded and notified.
   - The method is `door_poster`.
6. **Personal codes: rotating or static** (board 10 Q5).
   - The owner's `member_code_mode` defaults to `rotating`. The rules live
     in the pure `MemberCodePolicy`.
   - **Rotating:** `MemberCode`, `"M1" ‖ base64url(user ‖ HMAC(box member
     key, "member:v1" ‖ user ‖ window))`, with 30 s windows and ±1 grace.
     No Wallet: adding a card answers `wallet_requires_static_code` (409).
   - **Static:** one row per member and box in `facility_member_codes`
     (serial, `revoked_at`, reason; at most one active). The code is
     `StaticMemberCode`, `prefix ‖ base64url(serial ‖ HMAC(box member key,
     "member-static:v1" ‖ channel ‖ serial))`. It is `S1` in the app and
     `W1` on a Wallet card. Both forms name the same row; the channel only
     tells the desk which method to record (`member_qr` or `wallet`).
   - Codes are issued lazily.
   - The member resets their code (`POST …/me/check-in/code/reset`) and
     staff revoke it (`DELETE …/admin/check-in/members/:user/code`).
     Either way, the Wallet cards that carry the code are voided.
   - Switching static → rotating revokes every static code and card of the
     box. Switching rotating → static issues nothing until a code is needed.
   - The desk accepts a rotating code in any mode, and a static code only
     while the box is static.
7. **The desk.** `POST …/check-in/scan-member` with `code`, plus optional
   `location_id` and `auto`, identifies the member through `MemberCodes`.
   The member must be active in the box. `DeskAssessment` (pure) returns:
   - the `ResolveScan` decision;
   - problems: `frozen`, `package_expired`, `unpaid`, `no_spots` (a full
     class now here) and `nothing_to_check_in`;
   - the warning `payment_due` (grace);
   - `can_auto_check_in`: no problems and exactly one thing to check in to;
   - `override_allowed`: a problem and the owner's `desk_override`.

   With `auto: true` the desk checks in when all is fine.
   `POST …/check-in/members/:user` checks in. Its `override: true` is
   «Check-in παρ' όλα αυτά», allowed only by the owner rule and only for
   staff with `check_in` (the route capability). Otherwise it answers
   `check_in_problems` (409, with the problems) or `override_not_allowed`
   (403). An override check-in skips the entitlement reservation.
8. **Every check-in records its method.** The methods are `door_qr`,
   `door_poster`, `member_qr`, `wallet`, `desk_search` and `self`.
   - They are stored in `facility_check_ins.method` (check constraint;
     staff rows backfilled to `desk_search`) and
     `class_attendance_records.check_in_method` (nullable: coach roster
     marks have none).
   - A roster re-mark keeps the method.
9. **Owner rules.** «Ρυθμίσεις › Check-in» lives in
   `facility_check_in_settings` and is validated by the pure
   `CheckInRules`:
   - `window_before_minutes` / `window_after_minutes`: 0–120;
   - `open_gym_requires_package`;
   - `visitor_trial_offer`;
   - `desk_override`;
   - `door_rotation_seconds`: 15, 30 or 60;
   - `member_code_mode`.

   `GET/PUT …/admin/check-in/settings`; `UpdateCheckInRules` carries out a
   mode change.
10. **Wallet behind ports.**
    - `Wallet.Ports.PassBuilder` has an Apple and a Google adapter, and
      `Wallet.Ports.PassUpdater` has APNs and Google REST adapters. Both
      are configured per platform.
    - **Apple:** pass.json (a generic pass with a QR barcode, the next
      booking, up to 10 box locations and the PassKit web service URL) and
      images from the box branding: its logo when it is a PNG, otherwise
      generated colour tiles. manifest.json holds the SHA-1 of every file.
      The signature is a detached PKCS#7/CMS SignedData (SHA-256, signed
      attributes, the certificate and the WWDR intermediate, issuer and
      serial), written in DER with `:public_key`, for RSA or EC keys. The
      files are zipped with `:zip`.
    - **Google:** an RS256 «Save to Google Wallet» JWT with the generic
      class and object; object updates go through the REST API with a
      service-account OAuth token (PUT, falling back to POST).
    - `wallet_passes` (tenant) belongs to a member code. It holds the
      serial, the SHA-256 of the PassKit `authenticationToken` (derived from
      the Wallet key and the serial), `revoked_at` and `last_updated_at`.
      There is one active card per member, box and platform.
      `wallet_device_registrations` is its child table and holds no tenant
      column.
    - PassKit endpoints live under `/api/wallet/apple/v1/…`: register,
      unregister, changed serials (tag = unix µs), latest `.pkpass` with
      `Last-Modified` / 304, and log. The pass's own
      `Authorization: ApplePass …` is the only credential. Two definer
      functions cover the serial-only lookups.
    - Apple has no bearer header in Safari, so the `.pkpass` is fetched via
      a signed 10-minute link: `GET /api/wallet/passes/:token`.
    - `booking_made`, `booking_cancelled` and `attendance_recorded` touch
      the member's cards; `WalletPushJob` (one per pass per minute) tells
      the platform.
    - Credentials come from runtime env. Without them the platforms report
      unavailable and adding a card answers `wallet_not_configured` (503);
      everything else works.
    - Revoking a card (Εγώ › Συνδεδεμένες συσκευές) resets the member's
      code: a card stops scanning only when the code it carries ends. This
      voids every card that carries that code.
11. **Εγώ › Συνδεδεμένες συσκευές** (`GET /api/me/connected-devices`)
    returns:
    - which Wallet platforms can issue cards;
    - the person's cards at every box;
    - the ICS feed links (reset with the existing
      `POST /api/calendar/export-links/regenerate`);
    - integrations: Garmin `unavailable` (P2-M13 builds it), Apple Health
      and Health Connect `native_only`.

    Nothing claims a connection that doesn't exist.

## Rationale
- Codes signed from time need no table, no cleanup and no write per scan.
  The grace window absorbs clock skew and the turn of a window.
- Deriving keys from the application secret means a leaked database cannot
  mint codes.
- One pure `ResolveScan` keeps the door, the poster and the desk consistent
  and testable to the minute.
- The poster trades presence proof for having no screen, so it does the
  minimum that is safe: a booking already in its window.
- A rotating QR on a Wallet card would freeze one code, so ANR made it the
  owner's choice. Static codes are revocable rows, so «lost phone» has an
  answer: reset or revoke.
- Wallet credentials are platform-level (D10), so they belong in runtime
  config, not per box.

## Alternatives Considered
- **A table of door codes or nonces.** Rejected: it means a write per
  rotation and still needs a clock.
- **Phoenix.Token for door codes.** Rejected: the tokens are too long for a
  QR at a distance, and they can't be rotated per location.
- **Storing the HMAC key itself in the database.** Rejected: a database dump
  could then forge codes.
- **A Wallet barcode separate from the member code.** Rejected: ANR's Q5
  wants one persistent code shown both in the app and in Wallet. Revoking a
  card therefore resets the code.
- **A notification per visitor scan.** Rejected: it would be noisy. The
  notice is hourly per person and box, while the realtime line shows every
  scan.

## Consequences
- New tenant tables: `facility_check_in_settings`, `facility_visitor_scans`,
  `facility_member_codes` and `wallet_passes` (all FORCE RLS, in
  `Tenancy.Audit` and the Facility/Wallet tenant-data policies). Door and
  poster seeds and member-code serials are excluded from exports.
- `SubmitBooking` now publishes `booking_made`, and the payload of
  `booking_cancelled` carries `user_id`.
- New notification type: `check_in_visitor`.
- Undoing the check-in of a trial booking takes the trial back from
  attended to the status it had before the scan (`booked` or `no_show`,
  carried in the undo token); a trial converted meanwhile stays converted.
- The sound and green flash on a successful scan are web-only.

## Implementation Notes
- Config: `config :milos_training, :wallet`, read by
  `Infrastructure.Wallet.Credentials`; PEM values are either the text or a
  file path. The env names are:
  - Apple: `WALLET_APPLE_PASS_TYPE_ID`, `WALLET_APPLE_TEAM_ID`,
    `WALLET_APPLE_CERTIFICATE`, `WALLET_APPLE_PRIVATE_KEY`,
    `WALLET_APPLE_PRIVATE_KEY_PASSWORD`, `WALLET_APPLE_WWDR_CERTIFICATE`,
    `WALLET_APPLE_APNS_HOST`;
  - Google: `WALLET_GOOGLE_ISSUER_ID`, `WALLET_GOOGLE_SERVICE_ACCOUNT_EMAIL`,
    `WALLET_GOOGLE_PRIVATE_KEY`, `WALLET_GOOGLE_ORIGINS`.
- Tests:
  - The pure tests cover token windows, grace, rotation, offline batch
    expiry, poster codes, static codes, `MemberCodePolicy`, every
    `ResolveScan` branch at its edge minutes, `DeskAssessment`, pass.json,
    the manifest and the Google claims.
  - The PKCS#7 signature is verified both in Elixir and with
    `openssl cms -verify` against a test CA generated in the test (RSA and
    EC).
  - Controller and RLS-enforced integration tests cover every route.
