# ADR-195: One red error notice everywhere, and a language picker on the signed-out pages
Date: 2026-10-24
Status: Accepted

## Context
ANR (2026-10-24): "make the error messages and error boxes red-ish. For example, when somebody tries to log in and its credentials are invalid, should be red and prominent. And also add a language picker in the login/register page."

Errors were drawn by hand in each screen. Most used `--danger` text, but about 30 (the sign-in "invalid credentials" box among them, plus assignment, referral, finance and schedule screens) were tinted with the action blue (`--primary`/`--primary-strong`) or plain grey, so a failure looked like a hint. Signed-out pages followed the browser language with no way to change it, and a new account was always created in English, so the first signed-in screen switched language.

## Decision
1. **`ui/ErrorNotice`** is the only way to show an error to a person. Variants: `banner` (form, panel and page errors; icon, bold red text on a red-tinted box), `field` (compact box under one input), `text` (icon and red text for tight rows and table cells). It renders `role="alert"` (or `role="status"` with `live="polite"` for background refreshes) and takes `title` and an `action` (retry, dismiss).
2. **Three theme tokens** in `lib/theme.ts`: `dangerSurface`, `dangerBorder`, `dangerStrong` for Frost and Graphite. `dangerStrong` on `dangerSurface` and on `panel` is tested for WCAG AA (4.5:1).
3. Shared error helpers (`AuthNotice`, `StatusText tone="error"`, community `ErrorLine`, `QueryProblem`, shop `ErrorNotice`, local `ErrorText`s) render `ErrorNotice`, so their callers follow.
4. **Guard test** `ui/error-notice-guard.test.ts`: a hand-made `role="alert"` element fails unless it is a warning (a `--warning` style on the same tag).
5. **`auth/LanguagePicker`** (a `ui/Select` with the native language names) sits at the top of the sign-in/sign-up console and of `AuthShell` (forgot/reset password, business sign-up). It writes the `palee_locale` cookie and calls `router.refresh()` in a transition, so typed fields stay.
6. **Registration carries the language**: `POST /api/auth/register`, `register-admin` and `register-member` accept an optional `preferred_locale` (enum of supported locales); the web sends the page language. A signed-in account's saved language still wins at sign-in.

## Rationale
One component and three tokens make "what an error looks like" a single decision, re-dressable from `lib/theme.ts`. Red (Heat family) is the universal error colour; blue is reserved for actions. Persisting the chosen language on the account avoids a jarring switch back to English after sign-up.

## Alternatives Considered
- A global CSS rule on `[role="alert"]`: rejected, warnings also use that role and inline styles would override it.
- Mixing `--danger` with `color-mix()` per screen: rejected, it drifts and cannot be contrast-tested.
- Reloading the page on language change: rejected, it wipes what the person typed.

## Consequences
- Destructive buttons, red badges and counts keep `--danger`: they are actions or data, not errors.
- New error UI must use `ErrorNotice`; the guard catches hand-made alerts but not every red paragraph, so reviewers check new error text too.

## Implementation Notes
- Login stays in "sign in" mode after a language switch; the picker reuses the `Profile.languageLabel` string, so no new translations were needed.
