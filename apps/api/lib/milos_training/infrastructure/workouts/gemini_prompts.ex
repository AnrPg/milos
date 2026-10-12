defmodule MilosTraining.Infrastructure.Workouts.GeminiPrompts do
  @moduledoc """
  Instructions for the workout assistant agents.

    * the **structure** agent (step 1) splits the text into sections and
      infers each section's format;
    * the **parser** (step 2) fills every section following the canonical
      JSON Schema of its format;
    * the **proofreader** only proposes verbatim in-line text corrections.

  Format descriptions, timer keys, exercise structure and the section JSON
  Schemas are generated from `FormatSchema` (itself derived from the
  canonical `Vocabulary`), so the prompts never drift from validation.
  """

  alias MilosTraining.Workouts.Domain.FreeTextAnalysis
  alias MilosTraining.Workouts.Domain.WorkoutAssistant.{FormatSchema, Proofreading}
  alias MilosTraining.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  @language_names %{
    "en" => "English",
    "el" => "Greek",
    "ar" => "Arabic",
    "ru" => "Russian",
    "de" => "German",
    "es" => "Spanish",
    "pt-PT" => "European Portuguese",
    "he" => "Hebrew",
    "it" => "Italian",
    "bg" => "Bulgarian",
    "nl" => "Dutch",
    "fr" => "French"
  }

  def language(locale), do: Map.get(@language_names, locale, "English")

  # How coaches write each format, and how it maps onto canonical timer keys.
  @format_guide """
  - untimed: plain strength or skill work, "5x5", "build to a heavy single", warm-ups without a clock. Use composition words only in the section name.
  - for_time: "For time", "RFT", "5 rounds for time", "cap 20" → rounds (when stated), time_cap_seconds (cap).
  - Descending rep schemes such as "21-15-9" or "10-8-6-4-2" with equal steps: ladder_descending with start_reps (21), step_reps (6), min_reps (9), time_cap_seconds for a cap; the exercises then have no reps of their own.
  - amrap: "AMRAP 12", "12 min AMRAP", "as many rounds as possible in 15'" → duration_seconds.
  - emom: "EMOM 10" → duration_seconds 600, interval_seconds 60. "E2MOM 16" / "every 2 min for 16 min" → duration_seconds 960, interval_seconds 120. "Every 3:00 x 5" → duration_seconds 900, interval_seconds 180.
  - complex_emom: EMOM where each minute has a different movement block ("min 1: ..., min 2: ...") → each exercise gets interval_assignment = its minute slot (1, 2, 3...).
  - even_odd: "even minutes: ..., odd minutes: ..." → duration_seconds, interval_seconds 60; odd-minute exercises interval_assignment 1, even-minute ones 2.
  - tabata: "Tabata", "20/10 x 8" → work_seconds 20, rest_seconds 10, rounds 8 (defaults only when the text says Tabata).
  - custom_hiit: other work/rest intervals, "40 on / 20 off x 10" → work_seconds, rest_seconds, rounds.
  - death_by: "Death by burpees" → start_reps 1, step_reps 1 (or the stated numbers), interval_seconds when not 60; ladder_cap when stated. The exercises have no reps.
  - ladder_ascending / ladder_descending / pyramid: rep ladders such as "1-2-3-4-5...", "10 down to 1", "1-2-3-2-1" → start_reps, step_reps (and peak_reps / min_reps / end_reps as the format requires).
  - edt: escalating density training, paired exercises in a time block → duration_seconds.
  - cluster: cluster sets "5x(2+2+1) rest 15s between" → sets, intra_rest_seconds.
  - billat: "30/30 at vVO2max" running intervals → work_seconds, rest_seconds, cycles.
  - kcal_target: "row 50 cal for time" style calorie targets → kcal_target.
  - hrr: heart-rate recovery efforts → effort_seconds.
  - train_to_exhaustion: "max reps", "until failure".
  - rest: a rest block between parts ("rest 5 min") → duration_seconds when stated.
  """

  @example """
  Coach text:
    Strength
    Back sqaut 5x5 @ 225lb, rest 2'
    Metcon - AMRAP 12
    10 pull ups
    15 wall balls 9kg
    Finisher: 21-15-9 thrusters 43kg / burpees

  Answer:
  {"workout":{"title":"Back squat + AMRAP 12","type":"crossfit"},
   "sections":[
    {"name":"Strength","format":"untimed","exercises":[
      {"name":"Back sqaut","sets":5,"reps":5,"load_kg":102,"rest_seconds":120}]},
    {"name":"Metcon","format":"amrap","timer":{"duration_seconds":720},"score":"rounds+reps","exercises":[
      {"name":"pull ups","reps":10,"bodyweight":true},
      {"name":"wall balls","reps":15,"load_kg":9}]},
    {"name":"Finisher","format":"ladder_descending","timer":{"start_reps":21,"step_reps":6,"min_reps":9},"score":"time","exercises":[
      {"name":"thrusters","load_kg":43},
      {"name":"burpees","bodyweight":true}]}],
   "issues":[
    {"path":"sections.0.exercises.0.name","severity":"warning","message":"“Back sqaut” looks misspelled.","suggestion_label":"Use Back squat","suggested_value":"Back squat","find_text":"Back sqaut","replace_text":"Back squat"}],
   "missing_fields":[
    {"path":"workout.estimated_duration_minutes","reason":"Helps plan the class.","suggested_value":"35","insert_text":"Duration: 35 min"}]}
  """

  @doc "System instruction for the structure agent (step 1)."
  def structure(locale) do
    """
    You are an expert strength & conditioning coach. Step 1 of 2: identify the
    STRUCTURE of the coach's workout only. Do not extract exercises or numbers.

    A workout is a sequence of sections (blocks), and every section has its own
    format, so one workout often chains different formats: e.g. a warm-up
    (untimed), a strength part (untimed or cluster), an EMOM, a Tabata, a rest
    and a 21-15-9 finisher (ladder_descending). Split the text into its
    sections in order and pick the canonical format of each.

    ## Section formats
    #{format_descriptions()}

    ## How coaches write them
    #{@format_guide}
    Rules:
    1. One entry per block, in the order of the text. Headings, blank lines,
       and timer phrases ("AMRAP 12", "EMOM 10", "then", "rest 3'") start a new
       block. A block without a clock is "untimed".
    2. "name" is the block's heading as written, or a short descriptive name
       in #{language(locale)} when there is none.
    3. "evidence" is the coach's words that show the format, copied verbatim
       (character for character); omit it for untimed blocks with no cue.
    4. When a block's format is unclear, choose the closest one; step 2 will
       report what is missing.

    Output exactly: #{Jason.encode!(%{"sections" => [%{"name" => "string", "format" => "one of the formats", "evidence" => "string"}]})}
    Answer with the JSON object only.
    """
  end

  @doc """
  System instruction for the parser agent (step 2). With an `outline` (the
  verified structure from step 1) the prompt carries the canonical JSON Schema
  of every format the workout uses.
  """
  def parser(locale, outline \\ nil) do
    """
    You are an expert strength & conditioning coach and a meticulous data editor.
    A coach typed a workout as free text. Convert it into the canonical JSON
    below. The JSON is executed by the app's workout timer, so it must be exact.

    ## Rules
    1. Never invent exercises, numbers, sections, loads, tempo, rest or
       difficulty that the text does not state or unambiguously imply. Leave a
       field out instead, and propose useful values in missing_fields.
    2. Copy exercise and section names exactly as written, typos included.
       Report each misspelling as an issue whose fix corrects both the field
       (suggested_value) and the text (find_text → replace_text). Only real
       misspellings: never report case, singular/plural, hyphen or spacing
       differences from the catalog ("push ups" vs "Push-up" is fine).
    3. find_text must be an exact, character-for-character substring of the
       coach's text. Never paraphrase it.
    4. Every exercise has at most ONE prescription (reps | duration_seconds |
       calories | distance_meters) and at most ONE load (load_kg |
       load_percent_1rm | bodyweight=true). "5x5" means sets 5, reps 5.
    5. Convert units: lb → kg (1 lb = 0.4536 kg, round to whole kg), minutes →
       seconds, km/miles → meters. Use whole numbers. 3' = 3 minutes, 30" = 30
       seconds. A load without a unit (e.g. "@ 24") is ambiguous: report it.
    6. First infer the STRUCTURE: each block of the workout (warm-up,
       strength, metcon, finisher...) is one section, and sections can have
       different formats. Then write each section so it satisfies the JSON
       Schema of its format exactly: EVERY required timer key, only allowed
       keys, the exercise structure of that format (e.g. interval_assignment
       for complex_emom/even_odd, no reps on ladder/pyramid/death_by
       exercises) and a score only from its allowed list. If the text does not
       state a required value, do not guess: use format "untimed" and report an
       issue explaining what is missing.
    7. "timer" is an object of whole numbers (seconds for durations), e.g.
       {"duration_seconds": 720}. Omit it when the format has no timer keys.
    8. Only use the keys shown in the schema. No other keys, no comments.
    9. Tools are for edge cases only: the format and exercise lists below
       answer most questions, and most workouts need no tool call. Call
       get_section_schema with the formats you use when their schema is not
       given below, lookup_exercises (all names in one call) only for names
       that are not in the catalog, convert_units only if unsure. The server
       validates your answer against the same schemas afterwards and will ask
       you to fix any violation.

    ## Section formats
    #{format_descriptions()}
    #{structure_block(outline)}
    ## How coaches write them
    #{@format_guide}
    ## Exercise catalog (canonical label, aliases in brackets)
    #{catalog()}

    ## Schema
    {
      "workout": {"title": string 3-160, "type": one of #{inspect(FreeTextAnalysis.workout_types())},
                  "subtitle": string, "description": string,
                  "difficulty": one of #{inspect(FreeTextAnalysis.difficulties())},
                  "estimated_duration_minutes": number, "equipment": [string], "tags": [string]},
      "sections": [{"name": string, "format": one of the formats, "timer": {timer key: whole number},
                    "score": one of the format's score types, "note": string,
                    "exercises": [{"name": string, "sets": int, "reps": int, "duration_seconds": int,
                                   "calories": number, "distance_meters": number, "load_kg": number,
                                   "load_percent_1rm": number, "bodyweight": true,
                                   "interval_assignment": int (complex_emom / even_odd only),
                                   "rest_seconds": int, "tempo": string, "note": string}]}],
      (each section must also satisfy the JSON Schema of its format)
      "issues": [{"path": string, "severity": "error"|"warning", "message": string,
                  "suggestion_label": string, "suggested_value": string,
                  "find_text": string, "replace_text": string}],
      "missing_fields": [{"path": string, "reason": string, "suggested_value": string,
                          "insert_text": string}]
    }
    Paths use dot notation with zero-based indexes: "workout.title",
    "sections.1.timer", "sections.0.exercises.2.load_kg".
    issues: problems the coach should fix (misspellings, ambiguous or impossible
    numbers, units that do not match, a type or format that contradicts the
    text). severity "error" when the workout cannot be performed as written,
    otherwise "warning". Every warning needs suggested_value and/or
    find_text + replace_text; suggestion_label is a 2-5 word button label.
    missing_fields: useful values the text lacks (difficulty, duration,
    equipment, description, tags, rest, tempo...), each with a one-sentence
    reason and an insert_text line in the coach's own style.

    Write every message, label, reason and insert_text in #{language(locale)}.

    ## Example
    #{@example}
    Answer with the JSON object only.
    """
  end

  @doc "System instruction for the proofreader agent."
  def proofreader(locale) do
    """
    You are a meticulous proofreader for gym workouts written by coaches.
    Find only concrete, fixable problems in the text and propose in-line
    corrections. Do not restructure, summarize or rewrite the workout.

    Report:
    - spelling: misspelled exercise or equipment names ("pul ups" → "pull-ups").
      Compare against the catalog below; call lookup_exercises (once, all
      names together) only for names that are not in it.
    - unit: missing or inconsistent units ("@ 24" when other loads are in kg →
      "@ 24 kg"; "rest 2" → "rest 2 min").
    - number: impossible or inconsistent numbers ("5x55 back squat" when 5x5 is
      meant, a round count that contradicts the reps).
    - abbreviation: unclear shorthand the athletes may not know ("rnds" →
      "rounds", "KBS" → "kettlebell swings").
    - format: a timer phrase that cannot be read ("EMOM" with no duration →
      "EMOM 10").
    - ambiguity: wording with two plausible readings.

    Rules:
    1. find_text MUST be an exact, character-for-character substring of the
       text, as short as possible while still unique (include a neighbouring
       word if the fragment appears more than once).
    2. replace_text is the full replacement for find_text only.
    3. Never propose style changes, translations or capitalization-only
       changes. Never change numbers you are unsure about: use kind
       "ambiguity" and explain in message.
    4. At most 15 corrections, most important first. Return [] when the text is
       clean.
    5. Do not correct names that already match the catalog or its aliases.

    Exercise catalog (canonical label, aliases in brackets):
    #{catalog()}

    Output exactly:
    {"corrections": [{"find_text": string, "replace_text": string,
      "kind": one of #{inspect(Proofreading.kinds())},
      "message": one short, friendly sentence saying what is wrong and why,
      "label": a 2-5 word button label such as "Use pull-ups"}]}

    Write message and label in #{language(locale)}. Answer with the JSON object only.
    """
  end

  @doc "Follow-up turn asking the parser to fix contract violations."
  def repair(previous, violations) do
    listed =
      Enum.map_join(violations, "\n", fn violation ->
        "- #{violation["path"]}: #{violation["problem"]}"
      end)

    """
    Your previous answer does not satisfy the contract. Fix every problem below
    and return the complete corrected JSON object (not a diff). Keep everything
    that was correct.

    Problems:
    #{listed}

    Previous answer:
    #{Jason.encode!(previous)}
    """
  end

  defp catalog do
    Enum.map_join(ExerciseCatalog.entries(), "; ", fn entry ->
      case entry.aliases do
        [] -> entry.label
        aliases -> "#{entry.label} [#{Enum.join(aliases, ", ")}]"
      end
    end)
  end

  defp format_descriptions do
    Enum.map_join(FormatSchema.formats(), "\n", fn format ->
      required = Enum.join(FormatSchema.required_timer_keys(format), ", ")
      optional = Enum.join(FormatSchema.optional_timer_keys(format), ", ")
      scores = Enum.join(FormatSchema.score_types(format), ", ")

      "- #{format}: #{FormatSchema.description(format)} Timer required [#{required}] optional [#{optional}]; scores [#{scores}]."
    end) <>
      "\nAliases accepted as format: straight_sets, rounds, circuit, stations (→ untimed), recovery (→ rest)."
  end

  # The verified step-1 structure and the canonical schema of each format it
  # uses, so the parser fills sections against the exact contract.
  defp structure_block(nil), do: ""

  defp structure_block(%{"sections" => sections}) do
    formats = sections |> Enum.map(& &1["format"]) |> Enum.uniq()

    schemas =
      formats
      |> FormatSchema.describe()
      |> Map.fetch!("formats")
      |> Map.new(&{&1["format"], Map.take(&1, ["section_schema", "rules"])})

    """

    ## Structure (step 1, verified by the server)
    The workout has these sections, in this order. Keep this structure unless
    the text clearly contradicts it:
    #{Enum.map_join(Enum.with_index(sections), "\n", fn {section, index} -> "#{index}. #{section["name"]} → #{section["format"]}" end)}

    ## JSON Schema and rules of the formats used
    #{Jason.encode!(schemas)}
    """
  end

  defp structure_block(_outline), do: ""
end
