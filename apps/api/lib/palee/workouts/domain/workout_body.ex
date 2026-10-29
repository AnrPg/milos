defmodule Palee.Workouts.Domain.WorkoutBody do
  @moduledoc """
  What a workout says, in the shape of the way it was written, pure (ADR-224).

  A workout is written in one of four ways, and each has its own data. The
  flat workout fields (`free_text_body`, `sections[].exercises`, ...) are a
  superset of all three, so a reader cannot tell which fields matter. `body`
  is a tagged union keyed by `kind` that carries only what that way of
  writing has:

  * `free_text` — one text written with the assistant: `text`, the editor's
    rich `document` (TipTap/ProseMirror JSON: bold, underline, lists, colour,
    headings...) and the whole-workout `timer` when the coach set one.
    `structured` says whether the assistant also derived exercises from it.
  * `text_sections` — text written without the assistant (ADR-180): ordered
    `sections`, each with its `title` (nil when untitled), `text`, rich
    `document`, required `timer` and optional `scoring` metrics.
  * `structured` — exercises with every parameter (structured editor, Quick
    Text): ordered `sections` with `name`, `timer` and `exercises`, each
    exercise keeping its full prescription.
  * `plan` — written in the structured WOD editor (ADR-270, authoring mode
    `structured_plan`): ordered `sections` with `id`, `name`, the `plan`
    (`StructuredPlan`, the source of truth) and its `prescription`
    (`StructuredPlan.Prescription`, the canonical read model); the
    materialised exercises are left out.

  `summary/1` is the same union for lists: text is cut to an excerpt, the
  rich documents and exercise details are left out, and counts stay.
  """

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.Prescription

  @excerpt_length 280
  @free_text_timer_key "free_text_timer"

  @doc "The full body of a workout map (normalized workout, atom or string keys)."
  def build(workout) do
    case mode(workout) do
      "sectioned_text" ->
        %{kind: "text_sections", sections: workout |> sections() |> Enum.map(&text_section/1)}

      "structured_plan" ->
        %{kind: "plan", sections: workout |> sections() |> Enum.map(&plan_section/1)}

      "free_text" ->
        %{
          kind: "free_text",
          text: value(workout, :free_text_body),
          document: value(workout, :free_text_document),
          timer: free_text_timer(workout),
          structured: workout |> sections() |> Enum.any?(&has_exercises?/1)
        }

      _structured ->
        %{kind: "structured", sections: workout |> sections() |> Enum.map(&structured_section/1)}
    end
  end

  @doc "The body for lists: same kinds, excerpts instead of documents and exercises."
  def summary(workout) do
    case build(workout) do
      %{kind: "text_sections", sections: sections} ->
        %{
          kind: "text_sections",
          sections:
            Enum.map(sections, fn section ->
              %{
                title: section.title,
                excerpt: excerpt(section.text),
                timer: section.timer,
                scored: section.scoring != []
              }
            end)
        }

      %{kind: "plan", sections: sections} ->
        %{
          kind: "plan",
          sections:
            Enum.map(sections, fn section ->
              %{
                name: section.name,
                flow: plan_flow(section.plan),
                exercise_count: StructuredPlan.exercise_count(section.plan)
              }
            end)
        }

      %{kind: "free_text"} = body ->
        %{
          kind: "free_text",
          excerpt: excerpt(body.text),
          timer: body.timer,
          structured: body.structured
        }

      %{kind: "structured", sections: sections} ->
        %{
          kind: "structured",
          sections:
            Enum.map(sections, fn section ->
              %{
                name: section.name,
                timer: section.timer,
                exercise_count: length(section.exercises)
              }
            end)
        }
    end
  end

  @doc "The body's kind for an authoring mode."
  def kind(mode) when mode in ["sectioned_text", :sectioned_text], do: "text_sections"
  def kind(mode) when mode in ["free_text", :free_text], do: "free_text"
  def kind(mode) when mode in ["structured_plan", :structured_plan], do: "plan"
  def kind(_mode), do: "structured"

  def kinds, do: ["free_text", "text_sections", "structured", "plan"]

  defp text_section(section) do
    untitled? = get_in(map_value(section, :section_metadata), ["untitled"]) == true

    %{
      id: value(section, :id),
      title: if(untitled?, do: nil, else: value(section, :name)),
      text: value(section, :free_text_body) || "",
      document: value(section, :free_text_document),
      timer: value(section, :timer_preset),
      scoring: section |> map_value(:score_config) |> metrics()
    }
  end

  defp plan_section(section) do
    plan = map_value(section, :plan)

    %{
      id: value(section, :id),
      name: value(section, :name),
      plan: plan,
      prescription: plan |> Prescription.build() |> Prescription.to_json()
    }
  end

  defp plan_flow(%{} = plan), do: Map.get(plan, "flow")
  defp plan_flow(_plan), do: nil

  defp structured_section(section) do
    %{
      id: value(section, :id),
      name: value(section, :name),
      subtitle: value(section, :subtitle),
      timer: value(section, :timer_config),
      scoreable: value(section, :scoreable) == true,
      exercises: value(section, :exercises) || []
    }
  end

  defp mode(workout), do: workout |> value(:authoring_mode) |> to_string_or_nil()

  defp sections(workout), do: value(workout, :sections) || []

  defp has_exercises?(section) do
    section
    |> value(:exercises)
    |> List.wrap()
    |> Enum.any?(fn item -> to_string(value(item, :item_type) || "exercise") == "exercise" end)
  end

  defp free_text_timer(workout) do
    case map_value(workout, :workout_metadata) do
      %{} = metadata ->
        Map.get(metadata, @free_text_timer_key) || Map.get(metadata, :free_text_timer)

      _none ->
        nil
    end
  end

  defp metrics(%{} = config) do
    case value(config, :metrics) do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _none -> []
    end
  end

  defp metrics(_config), do: []

  defp excerpt(nil), do: nil

  defp excerpt(text) when is_binary(text) do
    trimmed = String.trim(text)

    if String.length(trimmed) > @excerpt_length,
      do: String.slice(trimmed, 0, @excerpt_length - 1) <> "…",
      else: trimmed
  end

  defp map_value(map, key) do
    case value(map, key) do
      %{} = nested -> nested
      _other -> nil
    end
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp value(%{} = map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_other, _key), do: nil
end
