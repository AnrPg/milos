# ADR-214: Form errors live in the form, on the field, in plain words
Date: 2026-10-27
Status: Accepted

## Context
ANR added a class from the onboarding checklist at 23:33 Athens time. The class
form always proposed 09:00 on the day clicked, so the request carried a start
that had already passed and the API answered `422 {scheduled_at: ["must be in
the future"]}`. The schedule page then showed "Check the highlighted values and
try again." in a banner behind the form, while the form itself marked nothing.

ANR's rules (2026-10-27):
- an error belongs inside the overlay form, never on the page behind it;
- a wrong field turns red and the reason sits right under it;
- messages explain what is wrong and how to fix it, without technical terms.

## Decision
1. **`lib/form-errors.ts`** turns a failed request into `FormErrors`
   (`fields` keyed as the API names them, plus one form-level `message`).
   - `formErrorsFrom(error, t, fields, {fallback, overrides})`: reasons of the
     fields a form shows land on them; reasons of other fields join the
     form-level message; the message says "look for the fields marked in red"
     only when a field is marked.
   - `explainFieldMessage` (in `i18n/presentation.ts`) maps the API's Ecto
     wording ("can't be blank", "must be greater than %{number}", "should be
     at most %{count} character(s)", "must be in the future", "has already been
     taken", …) to `Ui.formErr*` sentences in all 12 locales; anything unknown
     becomes a generic plain sentence, never the API's English.
   - `stillApplies` drops a field's mark as soon as its value differs from the
     one sent; `invalidFieldProps` + `fieldBorder` mark the control
     (`aria-invalid`, `aria-describedby`, red border).
2. **`ui/ErrorNotice` `FieldError`** renders the reason under a field.
3. **`ui/Dialog` `error`** shows the form-level notice inside the dialog, pinned
   above the footer so it stays in view while the body scrolls. A page that
   owns a dialog hides its own banner while the dialog is open.
4. **`localizeError`** no longer answers a field validation failure with
   "check the highlighted values": it lists the plain reasons
   (`apiErrorValidationFailedDetail`), so forms not yet on `formErrorsFrom`
   still say what was refused.
5. **Class starts** (`components/schedule/slot-time.ts`): a new class proposes
   09:00 on the box's clock, or the next open half hour at least 15 minutes
   ahead once that has passed; past days offer no "+ Slot"; the date picker
   starts at the box's today; a start that has passed is explained on the field
   («it is 23:33 at the box now (Athens)») and nothing is sent. The API keeps
   its own check. Series start no earlier than the box's today, and their end
   date, weekdays and excluded dates are checked before sending.

## Rationale
One building block keeps every form consistent and lets the remaining forms
move over one by one. Field-level messages come from the API's own validation,
so the client never has to duplicate every rule, while the rules a person hits
most (a past start, an end before the start) are caught before sending.

## Alternatives Considered
- Translating messages on the API (Gettext per request locale): larger change,
  and the web still has to map fields to controls; may follow later.
- Disabling past times in the picker only: the picker does not know the box's
  clock across days and still needs the explanation when time passes while the
  form is open.

## Consequences
Forms moved in this change: class and series (schedule), first class type,
class type removal mapping, member programming, workout folders, spaces, shop
order cancel, vendor organisation provision/settings/archive. Other forms keep
their inline errors and gain the plain-language fallback; move them to
`formErrorsFrom` when they are next touched.
