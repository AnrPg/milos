defmodule MilosTraining.Workouts.Domain.WorkoutAssistant.FormatSchema do
  @moduledoc """
  Canonical, machine-verifiable definition of every section format, as JSON
  Schema (draft 2020-12 subset, see `JsonSchema`).

  A workout is a sequence of sections and every section has its own format,
  so one workout can chain a warm-up (`untimed`), an `emom`, a `tabata` and a
  `ladder_descending`. Each format differs in:

    * its **timer** – which keys are required/optional, their kinds and limits;
    * its **exercise structure** – e.g. `complex_emom` exercises carry the
      interval slot they run in, ladder exercises take their reps from the
      ladder, Tabata stations take their duration from the work interval;
    * its **scoring** – which score types make sense;
    * cross-field **rules** JSON Schema cannot express (interval ≤ duration,
      a descending ladder starts above its minimum...).

  Everything derives from `WorkoutDsl.Vocabulary` (the timer specs the
  backend validates and executes with), so the agent, the strict `Contract`
  and the timer engine share one source of truth. Shapes use the assistant's
  field names (`timer`, `score`, `reps`, `load_kg`...); `FreeTextAnalysis`
  maps them onto the canonical section/exercise model.
  """

  alias MilosTraining.Workouts.Domain.{FreeTextAnalysis, JsonSchema}
  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  @schema_id "https://milos.training/schemas/workout-assistant/v1"

  # How each format runs on the athlete's clock, in words the agent can map
  # coach phrasing onto. Kept next to the schema so both stay in sync.
  @descriptions %{
    "untimed" =>
      "No clock. Strength sets, skills, warm-up or cool-down. Exercises are done in order with their own sets × reps.",
    "for_time" =>
      "Clock counts up until all the work is done. Optional rounds repeat the whole exercise list; optional time_cap_seconds stops it. \"3 RFT\", \"For time\".",
    "train_to_exhaustion" => "Work until failure (max reps / max rounds), progression is manual.",
    "kcal_target" =>
      "Accumulate kcal_target calories as fast as possible (counts up, optional cap). \"50 cal row for time\".",
    "emom" =>
      "Every interval_seconds for duration_seconds, ALL the section's exercises are done at the start of every interval. \"EMOM 10\" → interval 60, duration 600; \"E2MOM x 5\" → interval 120, duration 600.",
    "complex_emom" =>
      "Rotating EMOM: each interval runs ONE slot and the slots repeat in order. Every exercise carries interval_assignment = its slot (1, 2, 3...). \"EMOM 12: min 1 X, min 2 Y, min 3 Z\" → interval 60, duration 720, X=1, Y=2, Z=3.",
    "even_odd" =>
      "Alternating intervals (E/O MOM): interval_assignment 1 = odd intervals, 2 = even intervals. \"EOMOM 10: odd 12 cal row, even 10 burpees\".",
    "billat" =>
      "Running/erg intervals: cycles × (work_seconds hard, rest_seconds easy). \"30/30 x 20\" → work 30, rest 30, cycles 20.",
    "amrap" =>
      "As many rounds (and reps) as possible of the exercise list in duration_seconds; the clock counts down.",
    "edt" =>
      "Escalating density training: a pair of exercises alternated for duration_seconds, most total reps.",
    "death_by" =>
      "Every interval (default 60 s) n you do start_reps + (n − 1) × step_reps until you fail. \"Death by burpees\" → start_reps 1, step_reps 1. Exercises carry no reps.",
    "tabata" =>
      "rounds × (work_seconds work / rest_seconds rest); classic 8 × 20 s / 10 s. Exercises are stations rotated through the work intervals and take their duration from work_seconds.",
    "custom_hiit" =>
      "Like tabata with custom numbers: rounds × (work_seconds / rest_seconds), e.g. \"40/20 x 10\". Stations take their duration from work_seconds.",
    "cluster" =>
      "Cluster sets: sets clusters with intra_rest_seconds between mini-sets of cluster_reps; the cluster defines the sets, exercises carry reps and load only.",
    "hrr" =>
      "Heart-rate recovery: effort_seconds hard, then recover until the heart rate drops (hr_drop_target / recovery_cap_seconds).",
    "ladder_ascending" =>
      "Reps climb from start_reps by step_reps each round (until end_reps, ladder_cap or the time cap). \"1-2-3-4...\" → start 1, step 1. Exercises carry no reps.",
    "ladder_descending" =>
      "Reps fall from start_reps by step_reps down to min_reps. \"21-15-9\" → start 21, step 6, min 9; \"10 to 1\" → start 10, step 1, min 1. Exercises carry no reps.",
    "pyramid" =>
      "Reps climb from start_reps (default step_reps) to peak_reps by step_reps, then back down. \"2-4-6-8-6-4-2\" → start 2, step 2, peak 8. Exercises carry no reps.",
    "rest" =>
      "Recovery block between sections: a countdown of duration_seconds or a recovery_condition. Never has exercises."
  }

  @timer_key_descriptions %{
    duration_seconds: "total length of the block in seconds",
    interval_seconds: "length of one interval in seconds (EMOM = 60, E2MOM = 120)",
    interval_pattern_seconds:
      "window lengths in seconds when they differ, repeated in order (e.g. [60, 120])",
    time_cap_seconds: "time cap in seconds",
    transition_seconds: "changeover time between stations or rounds in seconds",
    rest_seconds: "rest in seconds",
    work_seconds: "work interval in seconds",
    rounds: "number of rounds",
    cycles: "number of work/rest cycles",
    sets: "number of sets",
    intra_rest_seconds: "rest between mini-sets of a cluster in seconds",
    effort_seconds: "effort duration in seconds",
    start_reps: "reps of the first round/interval",
    step_reps: "reps added (or removed) each round/interval",
    min_reps: "reps of the last round of a descending ladder",
    end_reps: "reps of the last round of an ascending ladder",
    peak_reps: "reps at the top of the pyramid",
    ladder_cap: "highest round/rep count to stop at",
    kcal_target: "calories to accumulate",
    pr_zone_rounds: "rounds that count as the PR zone",
    max_windows: "maximum number of intervals",
    target_rounds: "target rounds",
    cluster_reps: "reps per mini-set",
    scoring_mode: "how the EMOM is scored",
    amrap_scoring_style: "how AMRAP windows are aggregated",
    hr_zone: "target heart-rate zone (1–5)",
    hr_drop_target: "heart-rate drop in bpm that ends recovery",
    recovery_cap_seconds: "maximum recovery time in seconds",
    recovery_condition: "what ends the rest (e.g. \"HR below 120\")",
    target_distance_meters: "target distance per work interval in meters",
    target_pace: "target pace (text, e.g. \"1:45/500m\")"
  }

  # Exercise fields a format takes from its timer instead.
  @forbidden_exercise_keys %{
    "ladder_ascending" => %{"reps" => "the ladder (start_reps/step_reps) sets the reps"},
    "ladder_descending" => %{"reps" => "the ladder (start_reps/step_reps/min_reps) sets the reps"},
    "pyramid" => %{"reps" => "the pyramid (start_reps/step_reps/peak_reps) sets the reps"},
    "death_by" => %{"reps" => "death_by sets the reps (start_reps/step_reps)"},
    "tabata" => %{"duration_seconds" => "the work interval (work_seconds) sets the duration"},
    "custom_hiit" => %{"duration_seconds" => "the work interval (work_seconds) sets the duration"},
    "billat" => %{"duration_seconds" => "the work interval (work_seconds) sets the duration"},
    "hrr" => %{"duration_seconds" => "effort_seconds sets the duration"},
    "cluster" => %{"sets" => "the cluster's sets set the number of sets"}
  }

  ## Public API

  def schema_id, do: @schema_id
  def formats, do: Vocabulary.section_formats()

  def description(format), do: Map.get(@descriptions, canonical(format))

  @doc "Canonical format name for a format or alias (e.g. \"circuit\" → \"untimed\"), or nil."
  def canonical(format) when is_binary(format) do
    case Vocabulary.resolve_format(format) do
      {:ok, canonical, _composition} -> canonical
      {:error, _reason} -> nil
    end
  end

  def canonical(_format), do: nil

  @doc "Required timer keys: what the timer engine and the DSL both need."
  def required_timer_keys(format) do
    (Vocabulary.required_timer_fields(format) ++ Vocabulary.required_dsl_timer_fields(format))
    |> Enum.uniq()
    |> Enum.map(&Atom.to_string/1)
  end

  def optional_timer_keys(format) do
    format
    |> Vocabulary.optional_timer_fields()
    |> Enum.map(&Atom.to_string/1)
    |> Kernel.--(required_timer_keys(format))
  end

  def score_types(format), do: Vocabulary.allowed_score_types(format)

  @doc "JSON Schema of one section of `format` (nil for an unknown format)."
  def section_schema(format) do
    case canonical(format) do
      nil -> nil
      canonical -> build_section_schema(canonical)
    end
  end

  @doc "JSON Schema of one exercise inside a section of `format`."
  def exercise_schema(format) do
    canonical = canonical(format) || "untimed"
    forbidden = Map.get(@forbidden_exercise_keys, canonical, %{})

    properties =
      base_exercise_properties()
      |> Map.merge(interval_assignment_property(canonical))
      |> Map.merge(
        Map.new(forbidden, fn {key, reason} ->
          {key, %{"not" => %{}, "description" => "must be omitted: #{reason}"}}
        end)
      )

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["name" | interval_assignment_required(canonical)],
      "properties" => properties
    }
  end

  @doc """
  JSON Schema of the whole assistant answer. Sections are a `oneOf` over the
  given formats (all formats by default), discriminated by `format`.
  """
  def answer_schema(formats \\ formats()) do
    formats = formats |> Enum.map(&canonical/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$id" => @schema_id,
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(workout sections issues missing_fields),
      "properties" => %{
        "workout" => workout_schema(),
        "sections" => %{
          "type" => "array",
          "description" =>
            "The workout in order; every section is one block with its own format, so different formats can follow each other.",
          "items" => %{"oneOf" => Enum.map(formats, &%{"$ref" => "#/$defs/section_#{&1}"})}
        },
        "issues" => %{"type" => "array"},
        "missing_fields" => %{"type" => "array"},
        "assumptions" => %{
          "type" => "array",
          "description" =>
            "every value you inferred rather than read (conventions, computed values, expanded abbreviations)",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["path", "message"],
            "properties" => %{"path" => %{"type" => "string"}, "message" => %{"type" => "string"}}
          }
        }
      },
      "$defs" => Map.new(formats, &{"section_#{&1}", build_section_schema(&1)})
    }
  end

  @doc "Shape of the structure (outline) step: the sections and their formats."
  def outline_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["sections"],
      "properties" => %{
        "sections" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 20,
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(name format),
            "properties" => %{
              "name" => %{"type" => "string", "minLength" => 1, "maxLength" => 160},
              "format" => %{"enum" => formats()},
              "intent" => %{
                "type" => "string",
                "maxLength" => 300,
                "description" =>
                  "one sentence: what the coach means this block to be, including parameters written elsewhere in the text"
              },
              "evidence" => %{
                "type" => "string",
                "description" => "the coach's words that show the format, copied verbatim"
              }
            }
          }
        }
      }
    }
  end

  @doc """
  Verifies the structure step's answer: every section has a name and a known
  format (aliases are resolved to canonical names); evidence is kept only when
  it is verbatim in `source`. Returns `{:ok, outline}` or `{:error, violations}`.
  """
  def verify_outline(%{"sections" => sections} = raw, source)
      when is_list(sections) and is_binary(source) do
    outline = %{
      "sections" =>
        Enum.map(sections, fn
          %{} = section ->
            section
            |> Map.take(~w(name format evidence intent))
            |> Map.update("format", nil, &(canonical(&1) || &1))
            |> then(fn section ->
              evidence = Map.get(section, "evidence")

              if is_binary(evidence) and evidence != "" and String.contains?(source, evidence),
                do: section,
                else: Map.delete(section, "evidence")
            end)

          other ->
            other
        end)
    }

    case JsonSchema.validate(outline_schema(), Map.merge(raw, outline)) do
      [] -> {:ok, outline}
      violations -> {:error, violations}
    end
  end

  def verify_outline(_raw, _source),
    do: {:error, [%{"path" => "sections", "problem" => "is required and must be an array"}]}

  @doc """
  Self-describing definition for the agent tool: what each format means, how
  it runs, its JSON Schema and the extra rules the server enforces.
  """
  def describe(formats) do
    requested = formats |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.take(19)

    {known, unknown} =
      Enum.reduce(requested, {[], []}, fn format, {known, unknown} ->
        case canonical(format) do
          nil -> {known, [format | unknown]}
          canonical -> {[{format, canonical} | known], unknown}
        end
      end)

    %{
      "schema_id" => @schema_id,
      "formats" =>
        known
        |> Enum.reverse()
        |> Enum.uniq_by(&elem(&1, 1))
        |> Enum.map(fn {requested_as, canonical} ->
          %{
            "format" => canonical,
            "requested_as" => requested_as,
            "how_it_runs" => Map.fetch!(@descriptions, canonical),
            "required_timer_keys" => required_timer_keys(canonical),
            "optional_timer_keys" => optional_timer_keys(canonical),
            "score_types" => score_types(canonical),
            "rules" => rule_descriptions(canonical),
            "section_schema" => build_section_schema(canonical)
          }
        end),
      "unknown_formats" => Enum.reverse(unknown),
      "known_formats" => formats()
    }
  end

  @doc """
  Cross-field rules for a section whose shape is already valid. `section` uses
  the assistant shape with `timer` as an object.
  """
  def rule_violations(%{} = section, path) do
    format = canonical(Map.get(section, "format"))
    timer = Map.get(section, "timer")
    timer = if is_map(timer), do: timer, else: %{}
    exercises = Map.get(section, "exercises")
    exercises = if is_list(exercises), do: Enum.filter(exercises, &is_map/1), else: []

    format
    |> rules()
    |> Enum.flat_map(fn {_description, check} -> check.(timer, exercises, path) end)
  end

  def rule_violations(_section, _path), do: []

  ## Section schema

  defp build_section_schema(format) do
    required_timer = required_timer_keys(format)
    scores = score_types(format)

    properties =
      %{
        "name" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 160,
          "description" => "block name as written, or a short descriptive one"
        },
        "format" => %{"const" => format},
        "timer" => timer_schema(format),
        "note" => %{"type" => "string", "maxLength" => 2000},
        "exercises" => exercises_schema(format)
      }
      |> then(fn properties ->
        if scores == [],
          do:
            Map.put(properties, "score", %{
              "not" => %{},
              "description" => "#{format} is not scored"
            }),
          else:
            Map.put(properties, "score", %{
              "enum" => scores,
              "description" =>
                "what the athlete records for this block; omit if the text does not say"
            })
      end)

    %{
      "title" => format,
      "description" => Map.fetch!(@descriptions, format),
      "type" => "object",
      "additionalProperties" => false,
      "required" =>
        ["name", "format", "exercises"] ++ if(required_timer == [], do: [], else: ["timer"]),
      "properties" => properties
    }
  end

  defp timer_schema(format) do
    required = required_timer_keys(format)
    keys = required ++ optional_timer_keys(format)

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => required,
      "properties" => Map.new(keys, &{&1, timer_key_schema(&1)})
    }
  end

  defp timer_key_schema(key) do
    field = String.to_existing_atom(key)
    description = Map.get(@timer_key_descriptions, field, key)

    case Vocabulary.timer_value_kind(field) do
      :duration ->
        %{"type" => "integer", "minimum" => 1, "description" => description}

      :duration_list ->
        %{
          "type" => "array",
          "minItems" => 1,
          "items" => %{"type" => "integer", "minimum" => 1},
          "description" => description
        }

      :distance ->
        %{"type" => "number", "exclusiveMinimum" => 0, "description" => description}

      :integer ->
        %{"type" => "integer", "minimum" => 1, "description" => description}

      :enum ->
        %{"enum" => Vocabulary.timer_enum_values(field), "description" => description}

      :string ->
        %{"type" => "string", "minLength" => 1, "maxLength" => 120, "description" => description}
    end
  end

  defp exercises_schema("rest") do
    %{
      "type" => "array",
      "maxItems" => 0,
      "description" => "a rest block has no exercises; use []",
      "items" => exercise_schema("rest")
    }
  end

  defp exercises_schema(format) do
    %{"type" => "array", "maxItems" => 60, "items" => exercise_schema(format)}
  end

  ## Exercise schema

  defp base_exercise_properties do
    %{
      "name" => %{
        "type" => "string",
        "minLength" => 1,
        "maxLength" => 160,
        "description" => "canonical catalog name when it matches"
      },
      "sets" => %{"type" => "integer", "minimum" => 1},
      "reps" => %{"type" => "integer", "minimum" => 1},
      "duration_seconds" => %{"type" => "integer", "minimum" => 1},
      "calories" => %{"type" => "number", "exclusiveMinimum" => 0},
      "distance_meters" => %{"type" => "number", "exclusiveMinimum" => 0},
      "load_kg" => %{"type" => "number", "minimum" => 0},
      "load_percent_1rm" => %{"type" => "number", "exclusiveMinimum" => 0, "maximum" => 150},
      "bodyweight" => %{"type" => "boolean"},
      "rest_seconds" => %{"type" => "integer", "minimum" => 0},
      "tempo" => %{"type" => "string", "maxLength" => 40},
      "note" => %{"type" => "string", "maxLength" => 2000}
    }
  end

  defp interval_assignment_property("complex_emom") do
    %{
      "interval_assignment" => %{
        "type" => "integer",
        "minimum" => 1,
        "description" => "slot within the repeating cycle: 1 = first interval, 2 = second..."
      }
    }
  end

  defp interval_assignment_property("even_odd") do
    %{
      "interval_assignment" => %{
        "enum" => [1, 2],
        "description" => "1 = odd intervals, 2 = even intervals"
      }
    }
  end

  defp interval_assignment_property(format) do
    %{
      "interval_assignment" => %{
        "not" => %{},
        "description" =>
          "must be omitted: only complex_emom and even_odd assign exercises to intervals (#{format} runs every exercise each round)"
      }
    }
  end

  defp interval_assignment_required(format) when format in ~w(complex_emom even_odd),
    do: ["interval_assignment"]

  defp interval_assignment_required(_format), do: []

  ## Workout schema

  @doc "JSON Schema of the assistant's workout metadata object."
  def workout_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "title" => %{"type" => "string", "minLength" => 3, "maxLength" => 160},
        "type" => %{"enum" => FreeTextAnalysis.workout_types()},
        "subtitle" => %{"type" => "string", "maxLength" => 240},
        "description" => %{"type" => "string", "maxLength" => 10_000},
        "difficulty" => %{"enum" => FreeTextAnalysis.difficulties()},
        "estimated_duration_minutes" => %{"type" => "number", "exclusiveMinimum" => 0},
        "equipment" => %{"type" => "array", "items" => %{"type" => "string"}},
        "tags" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    }
  end

  ## Cross-field rules

  defp rule_descriptions(format), do: format |> rules() |> Enum.map(&elem(&1, 0))

  defp rules(format) when format in ~w(emom complex_emom even_odd) do
    [
      {"interval_seconds must not exceed duration_seconds", &interval_within_duration/3}
      | slot_rules(format)
    ]
  end

  defp rules("ladder_descending"),
    do: [{"start_reps must be greater than min_reps", &descending_ladder/3}]

  defp rules("ladder_ascending"),
    do: [{"end_reps, when given, must be at least start_reps", &ascending_ladder/3}]

  defp rules("pyramid"),
    do: [{"start_reps, when given, must not exceed peak_reps", &pyramid/3}]

  defp rules(_format), do: []

  defp slot_rules("complex_emom") do
    [
      {"interval_assignment must not exceed the number of intervals (duration_seconds / interval_seconds)",
       &slots_within_windows/3},
      {"slots must be consecutive starting at 1 (1, 2, 3...)", &consecutive_slots/3}
    ]
  end

  defp slot_rules(_format), do: []

  defp interval_within_duration(timer, _exercises, path) do
    with interval when is_integer(interval) <- Map.get(timer, "interval_seconds"),
         duration when is_integer(duration) <- Map.get(timer, "duration_seconds"),
         true <- interval > duration do
      [
        violation(
          "#{path}.timer.interval_seconds",
          "must not exceed duration_seconds (#{duration})"
        )
      ]
    else
      _ -> []
    end
  end

  defp slots_within_windows(timer, exercises, path) do
    interval = Map.get(timer, "interval_seconds")
    duration = Map.get(timer, "duration_seconds")

    if is_integer(interval) and is_integer(duration) and interval > 0 do
      windows = max(ceil(duration / interval), 1)

      exercises
      |> Enum.with_index()
      |> Enum.flat_map(fn {exercise, index} ->
        case Map.get(exercise, "interval_assignment") do
          slot when is_integer(slot) and slot > windows ->
            [
              violation(
                "#{path}.exercises.#{index}.interval_assignment",
                "slot #{slot} never runs: the block has only #{windows} intervals"
              )
            ]

          _other ->
            []
        end
      end)
    else
      []
    end
  end

  defp consecutive_slots(_timer, exercises, path) do
    slots =
      exercises
      |> Enum.map(&Map.get(&1, "interval_assignment"))
      |> Enum.filter(&(is_integer(&1) and &1 > 0))
      |> Enum.uniq()
      |> Enum.sort()

    if slots == [] or slots == Enum.to_list(1..length(slots)),
      do: [],
      else: [
        violation(
          "#{path}.exercises",
          "interval_assignment slots #{inspect(slots)} must be 1..N without gaps"
        )
      ]
  end

  defp descending_ladder(timer, _exercises, path) do
    with start when is_integer(start) <- Map.get(timer, "start_reps"),
         min when is_integer(min) <- Map.get(timer, "min_reps"),
         true <- start <= min do
      [violation("#{path}.timer.min_reps", "must be lower than start_reps (#{start})")]
    else
      _ -> []
    end
  end

  defp ascending_ladder(timer, _exercises, path) do
    with start when is_integer(start) <- Map.get(timer, "start_reps"),
         finish when is_integer(finish) <- Map.get(timer, "end_reps"),
         true <- finish < start do
      [violation("#{path}.timer.end_reps", "must be at least start_reps (#{start})")]
    else
      _ -> []
    end
  end

  defp pyramid(timer, _exercises, path) do
    with start when is_integer(start) <- Map.get(timer, "start_reps"),
         peak when is_integer(peak) <- Map.get(timer, "peak_reps"),
         true <- start > peak do
      [violation("#{path}.timer.start_reps", "must not exceed peak_reps (#{peak})")]
    else
      _ -> []
    end
  end

  defp violation(path, problem), do: %{"path" => path, "problem" => problem}
end
