defmodule MilosTraining.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer do
  @moduledoc """
  `WorkoutTextAnalyzer` adapter backed by the Google Gemini `generateContent`
  API with a JSON response schema.

  Configuration (runtime):

      config :milos_training, :gemini,
        api_key: System.get_env("GEMINI_API_KEY"),
        model: System.get_env("GEMINI_MODEL", "gemini-3.8-flash")

  The key never leaves the server: browsers call the Phoenix endpoint, which
  calls Gemini. Output is untrusted and is validated by
  `MilosTraining.Workouts.Domain.FreeTextAnalysis`.
  """

  @behaviour MilosTraining.Workouts.Ports.WorkoutTextAnalyzer

  require Logger

  alias MilosTraining.Workouts.Domain.FreeTextAnalysis
  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"
  @default_model "gemini-3.8-flash"

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

  @impl true
  def analyze(text, options) do
    config = Application.get_env(:milos_training, :gemini, [])
    api_key = Keyword.get(config, :api_key)

    if blank?(api_key) do
      {:error, :analyzer_not_configured}
    else
      model = Keyword.get(config, :model) || @default_model
      request(text, Map.get(options, :locale, "en"), api_key, model, config)
    end
  end

  defp request(text, locale, api_key, model, config) do
    body = %{
      systemInstruction: %{parts: [%{text: system_prompt(locale)}]},
      contents: [%{role: "user", parts: [%{text: text}]}],
      generationConfig: %{
        temperature: 0.1,
        # JSON mode with the schema in the instructions: Gemini's constrained
        # `responseSchema` decoding returned truncated, degenerate objects for
        # this deeply optional schema, while plain JSON mode follows it well.
        responseMimeType: "application/json"
      }
    }

    request_options =
      [
        url: "#{@endpoint}/#{model}:generateContent",
        headers: [{"x-goog-api-key", api_key}],
        json: body,
        receive_timeout: Keyword.get(config, :receive_timeout, 60_000),
        retry: :transient,
        max_retries: 1
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))

    case Req.post(request_options) do
      {:ok, %Req.Response{status: 200, body: response}} ->
        decode(response)

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Gemini workout analysis failed with HTTP #{status}")
        {:error, :analyzer_unavailable}

      {:error, exception} ->
        Logger.warning("Gemini workout analysis failed: #{Exception.message(exception)}")
        {:error, :analyzer_unavailable}
    end
  end

  defp decode(%{"candidates" => [%{"content" => %{"parts" => parts}} | _rest]}) do
    parts
    |> Enum.map_join("", &Map.get(&1, "text", ""))
    |> Jason.decode()
    |> case do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _other -> {:error, :analyzer_invalid_response}
    end
  end

  defp decode(_response), do: {:error, :analyzer_invalid_response}

  defp system_prompt(locale) do
    language = Map.get(@language_names, locale, "English")

    formats =
      Enum.map_join(Vocabulary.section_formats(), "\n", fn format ->
        required = format |> Vocabulary.required_timer_fields() |> Enum.join(", ")
        optional = format |> Vocabulary.optional_timer_fields() |> Enum.join(", ")
        "- #{format}: required [#{required}] optional [#{optional}]"
      end)

    """
    You are an expert strength & conditioning coach and a meticulous data editor.
    A coach typed a workout as free text. Read it and return JSON that follows the
    response schema exactly. Never invent exercises, numbers or sections that the
    text does not state or clearly imply.

    ## Canonical schema
    workout: title (3-160 chars), type (one of: #{Enum.join(FreeTextAnalysis.workout_types(), ", ")}),
    subtitle, description, difficulty (one of: #{Enum.join(FreeTextAnalysis.difficulties(), ", ")}),
    estimated_duration_minutes (number), equipment (list), tags (list).
    sections: name, format, timer (list of {key, value}), note, exercises.
    exercise: name, sets, ONE of reps | duration_seconds | calories | distance_meters,
    ONE of load_kg | load_percent_1rm | bodyweight=true, rest_seconds, tempo, note.
    Convert pounds to kilograms and minutes to seconds. Use integers.
    Leave a field out when the text does not state it. Never fill tempo, rest,
    load or difficulty from general knowledge: propose those in missing_fields.
    Copy exercise and section names exactly as written, typos included; report
    each misspelling as an issue whose fix corrects both the field and the text.

    Section formats and their timer keys. Timer keys must be spelled exactly as
    listed; values are plain numbers (durations in seconds):
    #{formats}
    Use "untimed" for plain strength work. Use "for_time" for "for time"/RFT.

    ## Paths
    Refer to fields with dot paths and zero-based indexes, for example
    "title", "sections.0.timer", "sections.1.exercises.2.load_kg".

    ## issues
    Report every problem a coach should fix: typos in exercise names, ambiguous or
    impossible numbers, units that do not match, missing values that make the
    workout impossible to perform, a type or format that contradicts the text.
    For each issue give: path, severity ("error" when the workout cannot be
    performed or a required field is missing, otherwise "warning"), message (one
    short, friendly, actionable sentence that says what is wrong and how to fix
    it), suggestion_label (a 2-5 word button label such as "Use 100 kg"),
    suggested_value (the corrected value for the field at path, as text), and
    when the fix should also change the coach's text: find_text (an exact,
    verbatim substring of the coach's text) and replace_text (its replacement).
    Every warning MUST include suggested_value, and find_text/replace_text when
    the text itself is wrong (always for misspellings). Do not report an issue
    you cannot offer a fix for, unless it is an error.

    ## missing_fields
    Compare the workout with the full canonical schema and propose useful
    missing values (difficulty, estimated duration, equipment, description,
    tags, rest, tempo, timer settings...). For each give: path, reason (one short
    sentence on why it helps), suggested_value (as text) and insert_text (a short
    line the coach could add to the text, in the coach's own style).

    Write every message, label, reason and insert_text in #{language}.

    ## Output
    Answer with one JSON object that matches this JSON schema (Gemini schema
    notation, types in capitals) and nothing else:
    #{Jason.encode!(response_schema())}
    """
  end

  defp response_schema do
    string = %{type: "STRING"}
    number = %{type: "NUMBER"}
    strings = %{type: "ARRAY", items: string}

    exercise = %{
      type: "OBJECT",
      properties: %{
        name: string,
        sets: number,
        reps: number,
        duration_seconds: number,
        calories: number,
        distance_meters: number,
        load_kg: number,
        load_percent_1rm: number,
        bodyweight: %{type: "BOOLEAN"},
        rest_seconds: number,
        tempo: string,
        note: string
      },
      required: ["name"]
    }

    section = %{
      type: "OBJECT",
      properties: %{
        name: string,
        format: %{type: "STRING", enum: Vocabulary.section_formats()},
        timer: %{
          type: "ARRAY",
          items: %{
            type: "OBJECT",
            properties: %{key: string, value: string},
            required: ["key", "value"]
          }
        },
        note: string,
        exercises: %{type: "ARRAY", items: exercise}
      },
      required: ["name", "exercises"]
    }

    %{
      type: "OBJECT",
      properties: %{
        workout: %{
          type: "OBJECT",
          properties: %{
            title: string,
            type: %{type: "STRING", enum: FreeTextAnalysis.workout_types()},
            subtitle: string,
            description: string,
            difficulty: %{type: "STRING", enum: FreeTextAnalysis.difficulties()},
            estimated_duration_minutes: number,
            equipment: strings,
            tags: strings
          }
        },
        sections: %{type: "ARRAY", items: section},
        issues: %{
          type: "ARRAY",
          items: %{
            type: "OBJECT",
            properties: %{
              path: string,
              severity: %{type: "STRING", enum: ["error", "warning"]},
              message: string,
              suggestion_label: string,
              suggested_value: string,
              find_text: string,
              replace_text: string
            },
            required: ["path", "severity", "message"]
          }
        },
        missing_fields: %{
          type: "ARRAY",
          items: %{
            type: "OBJECT",
            properties: %{
              path: string,
              reason: string,
              suggested_value: string,
              insert_text: string
            },
            required: ["path", "reason", "suggested_value"]
          }
        }
      },
      required: ["workout", "sections", "issues", "missing_fields"]
    }
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
