# ADR-223: A workout's body has its own shape for each way of writing it
Date: 2026-10-28
Status: Accepted

## Context
ANR (2026-10-28) looked at `GET /admin/workouts` for two WODs written in text
sections and saw sections with only `name`, `order` and an empty `exercises`
list: no text, no timer, `content: []`. The library's preview drawer, built
from that list, showed «Η προεπισκόπηση WOD ελεύθερου κειμένου θα εμφανιστεί
εδώ» instead of the WOD.

Two problems:
- the list summary kept only structured data (exercise counts), and the
  normalized workout never carried a free-text WOD's text;
- the workout shape is a superset of three ways of writing (free text with the
  assistant, text sections without it, structured exercises), so a reader
  cannot tell which fields hold the WOD.

## Decision
Every workout response carries `body`, a union keyed by `kind`
(`Palee.Workouts.Domain.WorkoutBody`, OpenAPI `WorkoutBody` with a `kind`
discriminator):

| kind | data |
|---|---|
| `free_text` | `text`, rich `document` (TipTap JSON), whole-workout `timer`, `structured` (the assistant also derived exercises) |
| `text_sections` | ordered `sections`: `title` (null when untitled), `text`, rich `document`, `timer` (required), `scoring` metrics |
| `structured` | ordered `sections`: `name`, `subtitle`, `timer`, `scoreable`, `exercises` with every prescription field |

Lists (`GET /admin/workouts`) carry `body` in summary form
(`WorkoutBodySummary`): the same kinds with text cut to an `excerpt`,
per-section timers and `scored`/`exercise_count`, never the rich documents.

The flat fields (`sections`, `free_text_body`, `free_text_document`, …) stay
for existing clients (web, mobile); new readers use `body`.

The web library preview loads the full workout when opened and shows text
sections one by one (title or «Ενότητα N», timer, scoring metrics, the text
with the coach's formatting: bold, italic, underline, strike, highlight and
text colours blended with the theme so they read in light and dark, lists,
headings, quotes, alignment).

## Rationale
A tagged union documents in the schema which data belongs to which way of
writing, lets clients switch on one field, and keeps lists light. Building it
from the stored columns needs no migration: the data was always stored, only
the responses dropped it.

## Alternatives Considered
- Replacing the flat fields with `body` only: breaks the mobile app and
  every web reader at once.
- Storing a separate typed table per mode: a large migration for data that is
  already stored correctly.
