# ADR-175: Voice logging
Date: 2026-10-21
Status: Accepted

## Context
Plan §5 P3-M13 and decision D10 (`docs/plans/redesign-phase-3-depth.md`): a
record button in `Νέα καταχώρηση`, transcription, a parsed draft, and the
member confirms to save. Plan §6 and vision §8.6 require that voice
recordings are not kept after transcription. D9 asks for provider-agnostic
ports that reuse the gym's own AI key and the `ai_usage` meter (ADR-152),
off unless the gym enabled the assistant. P3-M12 (ADR-174) introduced the
gym's AI settings row (`organization_ai_settings`: encrypted key,
`key_status`, model override, per-feature switches) and the Claude API
adapter pattern; this milestone builds on it.

## Decision
1. **New bounded context `VoiceLog`** (no tables): `Domain.Clip` (checks the
   clip), `Domain.Draft` (validates the parser answer into a draft),
   `Domain.VoicePolicy` (switch and daily cap), two ports with facades:
   `Ports.SpeechTranscriber` (`transcribe(clip, options)`) and
   `Ports.LogDraftParser` (`parse(input, options)`), configured as
   `:speech_transcriber` and `:log_draft_parser`. Test fakes:
   `FakeSpeechTranscriber`, `FakeLogDraftParser`.
2. **Transcription: server speech-to-text adapter on Gemini**
   (`Infrastructure.Ai.GeminiSpeechTranscriber`, `generateContent` with the
   clip inline, verbatim instruction, temperature 0, no thinking; model
   `GEMINI_TRANSCRIBE_MODEL`, default `gemini-2.5-flash`, platform key
   `GEMINI_API_KEY`). The Claude API takes no audio input, so the speech
   step cannot run on the gym's Anthropic key; the call is still metered for
   the gym (feature `voice_log`, agent `voice_transcribe`).
3. **Parsing: Claude API** (`Infrastructure.Ai.AnthropicLogDraftParser`),
   one Messages API call per recording on the gym's own key, JSON-schema
   constrained answer (`output_config.format`), effort `low`, server-side
   refusal fallbacks (`fallbacks: "default"`) on models that support them.
   Model: the gym's override or `ANTHROPIC_VOICE_MODEL` (default
   `claude-sonnet-5-5`). Only the transcript and the locale are sent, never
   who spoke; the system prompt treats the transcript as data, not
   instructions. Metered as agent `voice_parse` under the same
   `operation_id` as the transcription. A rejected key marks the gym's key
   `rejected` (as ADR-174 does); a good answer marks it `valid`.
4. **Endpoints** (member scope `/api/org/:slug/me/training-log`):
   `GET /voice` → `{voice: {available, enabled, max_seconds, daily_limit,
   remaining_today}}`; `POST /voice/drafts` with `{audio_base64, mime_type,
   duration_ms?, locale?}` → `{transcript, parsed, draft}`. Errors: 403
   `voice_log_unavailable`, 429 `voice_log_daily_limit`, 422
   `invalid_audio` / `audio_too_long` / `no_speech`, 503
   `transcription_unavailable`. **Nothing is written** by either endpoint
   except the usage meter and the key status.
5. **The member always reviews.** The draft opens in the existing log form
   (freeform source) with a notice «Πρόχειρο από φωνή. Έλεγξε και διόρθωσε
   πριν την αποθήκευση.» and a collapsed «Τι ακούστηκε». Saving is the
   normal `training_log.create` outbox command (ADR-118/120), then «Τι
   ένιωσες;» as for any logged workout.
6. **Gym switch:** `voice_enabled` on `organization_ai_settings` (migration
   `20261124100000`, default false), shown under Ρυθμίσεις › AI assistant
   next to the scaling switch. Switching it on needs a key; removing the key
   switches it off (same rules as `scaling_enabled`).
7. **Web recording through the platform layer:**
   `src/lib/platform/voice-recorder.ts` is the recorder port
   (`VoiceRecorder`: start/stop/cancel) with the browser/web-view adapter
   (getUserMedia + MediaRecorder, decoded and re-encoded in memory to 16 kHz
   mono 16-bit WAV by `wav.ts`) and `canRecordAudio()`. The store apps use
   the same code: the iOS shell declares `NSMicrophoneUsageDescription`, the
   Android shell `RECORD_AUDIO` and `MODIFY_AUDIO_SETTINGS`; no native plugin.
   `Permissions-Policy` now allows `microphone=(self)` (Next proxy and
   Caddy).
8. **Privacy:** the audio is never stored. It travels base64 in the JSON
   body (never a multipart temp file), lives in the request process's memory,
   is sent inline to the transcriber (not the provider's file store) and is
   dropped when the request ends. `config :phoenix, :filter_parameters`
   hides `audio*`, `transcript*`, `api_key`, `secret` and `password` from
   request logs; the adapters log only status codes. The transcript is
   returned to the member and kept only if they leave it in the entry.

## Decisions
Product and UX choices made without a board (owner's standing instruction:
most robust, least clutter).
- **Server speech-to-text, not browser/OS recognition:** the Web Speech API
  is missing in Firefox and in Android web views (so the Android app would
  need a native plugin), behaves differently per vendor and already sends
  audio to a vendor server on Chrome. MediaRecorder works in every current
  browser and both web views, so one path covers web and apps with one
  quality level, and the provider can be swapped behind the port.
- **Gemini for the speech step, Claude for parsing:** the Claude API has no
  audio input; Gemini already runs on the platform key for the free-text
  workout assistant, so no new provider or credential is needed. Parsing
  stays on the gym's own Claude key, as D9 asks.
- **WAV 16 kHz mono from the client:** accepted by every speech-to-text
  service (portable if the adapter changes) and small enough (≤ 1.9 MB for
  60 s) for a JSON body.
- **60-second limit:** enough to describe a session; keeps requests small
  and latency low.
- **Daily cap of 20 recordings per member** (UTC day, counted from the meter
  by transcription calls): bounds the gym's and the platform's cost without
  a new table; a call the provider did not bill does not count.
- **Its own switch, off by default:** members trigger the cost, so the gym
  opts in explicitly; scaling alone does not enable voice.
- **«Με φωνή» as a third tile in Προπόνηση, shown only when available:**
  same grid as the other kinds, no new screen, no disabled control; it is
  hidden when the gym has it off, the device cannot record or today's
  drafts are used up.
- **One button records and stops:** a single large control, timer «0:07 /
  1:00», auto-stop at the limit, «Άκυρο» drops the clip.
- **A failed parse still helps:** after a good transcription the member gets
  the form with the transcript as the Σχόλιο (`parsed: false`), never an
  error.
- **Missing title becomes «Προπόνηση»:** the freeform form requires a title;
  the member can change it.
- **`days_ago` (0–14) only moves the date:** spoken «χθες» sets yesterday at
  the current time; the member adjusts in the form.
- **No transcript editing step:** the member edits the parsed form itself,
  which is what gets saved; one review step only.
- **Neutral copy in all 12 locales; privacy line in the sheet:** «Η
  ηχογράφηση δεν αποθηκεύεται. Μένει μόνο ό,τι εγκρίνεις στη φόρμα.»

## Rationale
The ports keep both steps provider-agnostic and testable with fakes; the
draft is pure data validated in the domain, so an unreliable model answer
can never write anything. Reusing the gym's AI settings row and the meter
keeps one place for keys, switches and cost. Recording in the web layer
keeps one codebase for web and apps (D8).

## Alternatives Considered
- **Web Speech API / native speech plugin:** see Decisions; uneven support
  and a native plugin per platform.
- **A server STT on the gym's key:** impossible with an Anthropic key (no
  audio input); asking gyms for a second provider key adds setup for little
  gain.
- **Multipart upload:** Plug writes uploads to temporary files; JSON keeps
  the audio in memory only.
- **Auto-saving the parsed entry:** rejected by the plan and §8.6.
- **Storing audio for re-transcription or quality review:** rejected; no
  justification outweighs keeping health-adjacent voice data.

## Consequences
- New env vars (optional): `GEMINI_TRANSCRIBE_MODEL`,
  `ANTHROPIC_VOICE_MODEL`. Voice logging needs `GEMINI_API_KEY` on the
  platform and a gym key with the voice switch on.
- Price list: `gemini-2.5-flash` audio input is billed by Google above its
  text rate; the meter records it at the text rate (a known under-count,
  like ADR-174's cache-write note) until the price list learns modalities.
- `AiUsageStore.summarize/2` accepts `user_id` and `agent` filters.
- P3-M13 depends on P3-M12 (merged into this branch); merge P3-M12 first.

## Implementation Notes
- `MIX_TEST_PARTITION=19`; scoped tests only (owner's policy 2026-10-21).
- The member's locale is a hint to both steps; texts the parser writes
  (title, notes) follow it.
- Vitest: a module-level mock that rejects after a user interaction is
  reported as unhandled; the sheet takes `submit` and `recorderFactory`
  props so tests inject fakes instead.
