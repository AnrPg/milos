defmodule Palee.Workouts.Domain.SectionedText do
  @moduledoc """
  Workouts written without the assistant (ADR-179), pure.

  When a gym (or a coach, for one workout) turns the WOD assistant off, the
  workout is not parsed into exercises. The coach writes it as a list of text
  sections instead and picks one timer per section; the athlete runs those
  timers one section at a time.

  * A section has an optional title, its text (plain, plus the editor's
    TipTap JSON) and a timer preset (`TimerPresets`: the same shape the
    free-text and class timers use). The stopwatch (`untimed`) counts as a
    timer; a section without one cannot be published.
  * Publishing composes the workout's own `free_text_body` and
    `free_text_document` from the sections, so every screen that already
    shows a free-text workout (Box, class sheet, previews, goals, the icon
    suggester) shows a sectioned one without knowing about sections.
  """

  alias Palee.Execution.Domain.TimerPresets

  @mode "sectioned_text"
  @max_sections 30
  @max_title_length 120
  @max_body_bytes 20_000
  @free_text_timer_key "free_text_timer"

  def mode, do: @mode
  def max_sections, do: @max_sections
  def max_body_bytes, do: @max_body_bytes

  @doc "Whether publish params describe a sectioned workout."
  def sectioned?(%{} = params), do: value(params, :authoring_mode) == @mode
  def sectioned?(_params), do: false

  @doc """
  Validates the sections of a sectioned workout and returns the publish
  params with normalised sections and the composed body and document.

  Errors: `{:error, :no_sections}` or
  `{:error, {:invalid_text_sections, problems}}` where each problem is
  `%{section: index_from_1, problem: code}` and code is one of
  `text_required`, `text_too_long`, `title_too_long`, `timer_required`.
  """
  def prepare_publish(%{} = params) do
    case value(params, :sections) do
      [_ | _] = sections when length(sections) <= @max_sections ->
        sections
        |> Enum.with_index(1)
        |> Enum.map(fn {section, index} -> normalize_section(section, index) end)
        |> collect(params)

      [_ | _] ->
        {:error, {:invalid_text_sections, [%{section: nil, problem: "too_many_sections"}]}}

      _none ->
        {:error, :no_sections}
    end
  end

  defp collect(results, params) do
    case Enum.flat_map(results, fn
           {:error, problems} -> problems
           {:ok, _section} -> []
         end) do
      [] ->
        sections = Enum.map(results, fn {:ok, section} -> section end)

        {:ok,
         params
         |> Map.new(fn {key, item} -> {to_string(key), item} end)
         |> Map.put("sections", sections)
         |> Map.put("free_text_body", compose_body(sections))
         |> Map.put("free_text_document", compose_document(sections))
         |> Map.update("workout_metadata", %{}, &drop_whole_workout_timer/1)}

      problems ->
        {:error, {:invalid_text_sections, problems}}
    end
  end

  defp normalize_section(%{} = section, index) do
    title = section |> value(:name) |> trimmed()
    body = section |> value(:free_text_body) |> trimmed()
    preset = TimerPresets.parse(value(section, :timer_preset))

    problems =
      [
        body == "" && "text_required",
        byte_size(body) > @max_body_bytes && "text_too_long",
        String.length(title) > @max_title_length && "title_too_long",
        is_nil(preset) && "timer_required"
      ]
      |> Enum.filter(& &1)
      |> Enum.map(&%{section: index, problem: &1})

    if problems == [] do
      {:ok,
       %{
         "name" => if(title == "", do: Integer.to_string(index), else: title),
         "order" => index,
         "scoreable" => false,
         "free_text_body" => body,
         "free_text_document" => document(value(section, :free_text_document), body),
         "timer_preset" => preset,
         "section_metadata" => %{"untitled" => title == ""},
         "exercises" => []
       }}
    else
      {:error, problems}
    end
  end

  defp normalize_section(_section, index),
    do: {:error, [%{section: index, problem: "text_required"}]}

  @doc "The workout's plain text: each section's title (when it has one) above its text."
  def compose_body(sections) do
    Enum.map_join(sections, "\n\n", fn section ->
      if untitled?(section),
        do: section["free_text_body"],
        else: section["name"] <> "\n" <> section["free_text_body"]
    end)
  end

  @doc "The workout's rich text: a heading per titled section, then its own blocks."
  def compose_document(sections) do
    %{
      "type" => "doc",
      "content" =>
        Enum.flat_map(sections, fn section ->
          heading =
            if untitled?(section),
              do: [],
              else: [
                %{
                  "type" => "heading",
                  "attrs" => %{"level" => 3},
                  "content" => [%{"type" => "text", "text" => section["name"]}]
                }
              ]

          heading ++ blocks(section["free_text_document"])
        end)
    }
  end

  defp untitled?(section), do: get_in(section, ["section_metadata", "untitled"]) == true

  defp blocks(%{"content" => [_ | _] = content}), do: content
  defp blocks(_document), do: []

  # The editor's JSON when it is a document, else paragraphs from the text.
  defp document(%{"type" => "doc", "content" => content} = document, _body) when is_list(content),
    do: document

  defp document(%{type: "doc"} = document, body),
    do: document |> Map.new(fn {key, item} -> {to_string(key), item} end) |> document(body)

  defp document(_document, body) do
    %{
      "type" => "doc",
      "content" =>
        body
        |> String.split("\n")
        |> Enum.map(fn
          "" -> %{"type" => "paragraph"}
          line -> %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => line}]}
        end)
    }
  end

  # A sectioned workout times each section; a whole-workout timer left over
  # from free-text authoring would contradict them.
  defp drop_whole_workout_timer(%{} = metadata),
    do: metadata |> Map.delete(@free_text_timer_key) |> Map.delete(:free_text_timer)

  defp drop_whole_workout_timer(_metadata), do: %{}

  defp trimmed(text) when is_binary(text), do: String.trim(text)
  defp trimmed(_text), do: ""

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
