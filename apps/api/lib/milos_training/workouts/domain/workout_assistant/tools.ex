defmodule MilosTraining.Workouts.Domain.WorkoutAssistant.Tools do
  @moduledoc """
  Functions the workout assistant agents may call while reading a free-text
  workout (Gemini function calling). Pure and deterministic: the model asks,
  the server answers from canonical data, so agents never guess vocabulary.

    * `lookup_exercises` – match names against the canonical exercise catalog
      (exact, alias, or closest spellings) and report what each movement
      supports (load, distance, calories...).
    * `get_section_schema` – the canonical JSON Schema of one or more section
      formats (timer, exercise structure, scoring, cross-field rules), from
      `FormatSchema`, the same definition the server validates with.
    * `get_timer_format` – just the timer keys of one format (narrow view).
    * `convert_units` – lb/kg, minutes/seconds, km/miles/meters.
    * `validate_draft` – run the strict contract check on a draft answer, so
      the agent can fix problems before replying.
  """

  alias MilosTraining.Workouts.Domain.WorkoutAssistant.{Contract, FormatSchema}
  alias MilosTraining.Workouts.Domain.WorkoutDsl.{ExerciseCatalog, Vocabulary}

  @max_names 40

  @doc "Gemini `functionDeclarations` for the given tool names."
  def declarations(names) do
    Enum.map(names, &declaration/1)
  end

  def names,
    do: ~w(lookup_exercises get_section_schema get_timer_format convert_units validate_draft)

  @doc "Executes a tool call. Always returns a JSON-encodable map."
  def call(name, args, context \\ %{})

  def call("lookup_exercises", args, _context) do
    names =
      args
      |> arg("names")
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.take(@max_names)

    %{"results" => Enum.map(names, &lookup/1)}
  end

  def call("get_section_schema", args, _context) do
    args
    |> arg("formats")
    |> List.wrap()
    |> FormatSchema.describe()
  end

  def call("get_timer_format", args, _context) do
    format = arg(args, "format")

    case is_binary(format) && Vocabulary.resolve_format(format) do
      {:ok, canonical, composition} ->
        %{
          "format" => canonical,
          "composition" => composition,
          "required_keys" => keys(Vocabulary.required_timer_fields(canonical)),
          "optional_keys" => keys(Vocabulary.optional_timer_fields(canonical)),
          "value_kinds" =>
            canonical
            |> Vocabulary.allowed_timer_fields()
            |> Map.new(&{Atom.to_string(&1), value_kind(&1)})
        }

      _other ->
        %{"error" => "unknown_format", "known_formats" => Vocabulary.section_formats()}
    end
  end

  def call("convert_units", args, _context) do
    with value when is_number(value) <- number(arg(args, "value")),
         {:ok, result} <- convert(value, arg(args, "from"), arg(args, "to")) do
      %{"value" => result}
    else
      _ -> %{"error" => "unsupported_conversion", "supported" => ~w(lb kg min s h km mi m)}
    end
  end

  def call("validate_draft", args, context) do
    draft = decode_draft(arg(args, "draft_json") || arg(args, "draft"))
    source = Map.get(context, :source, "")

    case draft do
      %{} ->
        violations = Contract.check(draft, source)
        %{"valid" => violations == [], "violations" => violations}

      _other ->
        %{
          "valid" => false,
          "violations" => [%{"path" => "", "problem" => "draft must be an object"}]
        }
    end
  end

  def call(name, _args, _context), do: %{"error" => "unknown_tool", "tool" => name}

  @doc "Closest catalog entries for one exercise name."
  def lookup(name) do
    base = %{"query" => name}

    case ExerciseCatalog.resolve(name) do
      {:ok, entry, match} ->
        Map.merge(base, %{"match" => Atom.to_string(match), "exercise" => present(entry)})

      _not_exact ->
        candidates =
          ExerciseCatalog.entries()
          |> Enum.map(&{&1, similarity(name, &1)})
          |> Enum.filter(fn {_entry, score} -> score >= 0.82 end)
          |> Enum.sort_by(fn {_entry, score} -> -score end)
          |> Enum.take(3)
          |> Enum.map(fn {entry, score} ->
            entry |> present() |> Map.put("similarity", Float.round(score, 2))
          end)

        Map.merge(base, %{
          "match" => if(candidates == [], do: "none", else: "close"),
          "candidates" => candidates
        })
    end
  end

  defp present(entry) do
    %{
      "id" => entry.id,
      "label" => entry.label,
      "category" => entry.category,
      "supports" => entry.capabilities
    }
  end

  defp similarity(name, entry) do
    query = normalize(name)

    [entry.label | entry.aliases]
    |> Enum.map(&String.jaro_distance(query, normalize(&1)))
    |> Enum.max()
  end

  defp normalize(name),
    do: name |> String.downcase() |> String.replace(~r/[\s_-]+/u, " ") |> String.trim()

  defp convert(value, from, to) do
    factors = %{
      {"lb", "kg"} => 0.45359237,
      {"kg", "lb"} => 2.20462262,
      {"min", "s"} => 60,
      {"h", "s"} => 3600,
      {"s", "min"} => 1 / 60,
      {"km", "m"} => 1000,
      {"mi", "m"} => 1609.344,
      {"m", "km"} => 0.001
    }

    case Map.fetch(factors, {from, to}) do
      {:ok, factor} -> {:ok, Float.round(value * factor * 1.0, 2)}
      :error when from == to -> {:ok, value}
      :error -> :error
    end
  end

  defp value_kind(field) do
    case Vocabulary.timer_value_kind(field) do
      :enum -> %{"kind" => "enum", "values" => Vocabulary.timer_enum_values(field)}
      kind -> %{"kind" => Atom.to_string(kind)}
    end
  end

  defp keys(fields), do: Enum.map(fields, &Atom.to_string/1)

  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Float.parse(String.replace(value, ",", ".")) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp number(_value), do: nil

  defp decode_draft(%{} = draft), do: draft

  defp decode_draft(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = draft} -> draft
      _other -> nil
    end
  end

  defp decode_draft(_draft), do: nil

  defp arg(args, key) when is_map(args), do: Map.get(args, key)
  defp arg(_args, _key), do: nil

  defp declaration("lookup_exercises") do
    %{
      name: "lookup_exercises",
      description:
        "Match exercise names (as the coach wrote them) against the gym's canonical exercise catalog. Returns exact or alias matches, or the closest spellings with similarity, and which prescriptions each movement supports (reps, load, duration, distance, calories). Use it to detect misspellings and to know whether a load or distance makes sense.",
      parameters: %{
        type: "OBJECT",
        properties: %{names: %{type: "ARRAY", items: %{type: "STRING"}}},
        required: ["names"]
      }
    }
  end

  defp declaration("get_section_schema") do
    %{
      name: "get_section_schema",
      description:
        "Return the canonical, verifiable definition of section formats: how each runs on the clock, required and optional timer keys, the exercise structure (e.g. complex_emom exercises need interval_assignment, ladder exercises carry no reps), allowed score types, cross-field rules, and the JSON Schema a section of that format must satisfy. Call it with every format the workout uses before writing those sections.",
      parameters: %{
        type: "OBJECT",
        properties: %{
          formats: %{
            type: "ARRAY",
            items: %{type: "STRING", enum: FormatSchema.formats()},
            description: "Section formats to describe, e.g. [\"untimed\", \"emom\", \"tabata\"]"
          }
        },
        required: ["formats"]
      }
    }
  end

  defp declaration("get_timer_format") do
    %{
      name: "get_timer_format",
      description:
        "Return the canonical name, required and optional timer keys and value kinds for a section format such as amrap, emom, for_time, tabata, ladder_ascending or an alias like rounds/circuit.",
      parameters: %{
        type: "OBJECT",
        properties: %{format: %{type: "STRING"}},
        required: ["format"]
      }
    }
  end

  defp declaration("convert_units") do
    %{
      name: "convert_units",
      description: "Convert a value between lb/kg, min/s, h/s, km/m, mi/m.",
      parameters: %{
        type: "OBJECT",
        properties: %{
          value: %{type: "NUMBER"},
          from: %{type: "STRING", enum: ~w(lb kg min s h km mi m)},
          to: %{type: "STRING", enum: ~w(lb kg min s h km mi m)}
        },
        required: ["value", "from", "to"]
      }
    }
  end

  defp declaration("validate_draft") do
    %{
      name: "validate_draft",
      description:
        "Check a complete draft answer (the JSON object you intend to return, serialized as a JSON string) against the strict schema contract and the coach's text. Returns every violation with its path. Call it before answering and fix all violations.",
      parameters: %{
        type: "OBJECT",
        properties: %{draft_json: %{type: "STRING"}},
        required: ["draft_json"]
      }
    }
  end
end
