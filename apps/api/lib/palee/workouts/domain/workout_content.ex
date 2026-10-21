defmodule Palee.Workouts.Domain.WorkoutContent do
  @moduledoc """
  What a coach writes into a workout besides its prescription (ADR-140 §4).

  * **Οδηγίες** (`instructions`) for the workout, a section, a group or a
    header, with three more kinds of the same family: `scaling`
    (Κλιμάκωση), `safety` (Προσοχή) and `equipment` (Εξοπλισμός).
  * **Cue** (`cue`): technique advice beside one exercise or one of its
    scale variations; only there.
  * **Οδηγός coach** (`coach-brief`): for staff only, never sent to members.

  Content is a list of `%{type, body}` entries. The markers written before
  ADR-140 (`!note`, `!athlete-note`, `!coach-note`, `!scaling-note`,
  `!safety-note`, `!equipment-note`) are still accepted and normalised here,
  so pasted legacy text keeps working: `note` and `athlete-note` become a
  cue on an exercise and Οδηγίες anywhere else.
  """

  @types ~w(instructions scaling safety equipment cue coach-brief)
  @max_body_bytes 20_000

  @legacy %{
    "note" => :primary,
    "athlete-note" => :primary,
    "coach-note" => "coach-brief",
    "scaling-note" => "scaling",
    "safety-note" => "safety",
    "equipment-note" => "equipment"
  }

  @type level :: :workout | :section | :group | :header | :exercise | :variation

  def types, do: @types
  def max_body_bytes, do: @max_body_bytes

  @doc "Every marker the DSL writes, in the order an editor suggests them."
  def markers, do: Enum.map(@types, &"!#{&1}")

  @doc "Markers suggested at one level (a cue only beside an exercise)."
  def markers(level), do: level |> types_at() |> Enum.map(&"!#{&1}")

  def types_at(level) when level in [:exercise, :variation], do: @types -- ["instructions"]
  def types_at(_level), do: @types -- ["cue"]

  @doc """
  The canonical type of a written type at one level: `{:ok, type}`,
  `{:error, :cue_outside_exercise}` or `{:error, :unknown_content_type}`.
  Οδηγίες on an exercise are its cue.
  """
  def normalize_type(type, level) when is_binary(type) do
    type = type |> String.trim_leading("!") |> String.downcase()

    canonical =
      case Map.get(@legacy, type, type) do
        :primary -> primary(level)
        "instructions" -> primary(level)
        other -> other
      end

    cond do
      canonical not in @types -> {:error, :unknown_content_type}
      canonical == "cue" and not exercise_level?(level) -> {:error, :cue_outside_exercise}
      true -> {:ok, canonical}
    end
  end

  def normalize_type(_type, _level), do: {:error, :unknown_content_type}

  @doc "Whether a marker (with its `!`) is a content marker, current or legacy."
  def marker?(marker) when is_binary(marker) do
    type = String.trim_leading(marker, "!")
    String.starts_with?(marker, "!") and (type in @types or Map.has_key?(@legacy, type))
  end

  def marker?(_marker), do: false

  @doc "The kind of text a level's plain `note` field holds: its cue or its Οδηγίες."
  def primary(level) when level in [:exercise, :variation], do: "cue"
  def primary(_level), do: "instructions"

  @doc "Validates a stored content list for one level."
  def validate(content, level) when is_list(content) do
    if Enum.all?(content, &valid_entry?(&1, level)),
      do: :ok,
      else: {:error, :invalid_workout_content}
  end

  def validate(_content, _level), do: {:error, :content_must_be_a_list}

  @doc """
  What one audience sees: staff see everything; members never see a
  `coach-brief`.
  """
  def visible(content, :staff), do: content || []

  def visible(content, _audience),
    do: Enum.reject(content || [], &(type(&1) == "coach-brief"))

  def staff_only?(type), do: type == "coach-brief"

  @doc """
  A level's content including its plain `note` (what the structured editor
  writes): the note leads as the level's cue or Οδηγίες unless an entry of
  that kind is already there.
  """
  def with_note(content, note, level) do
    content = content || []
    primary = primary(level)

    if blank?(note) or Enum.any?(content, &(type(&1) == primary)),
      do: content,
      else: [%{"type" => primary, "body" => String.trim(note)} | content]
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""

  defp valid_entry?(entry, level) when is_map(entry) do
    body = Map.get(entry, :body) || Map.get(entry, "body")
    document = Map.get(entry, :document) || Map.get(entry, "document")

    type(entry) in types_at(level) and is_binary(body) and
      byte_size(body) in 1..@max_body_bytes and (is_nil(document) or is_map(document))
  end

  defp valid_entry?(_entry, _level), do: false

  defp type(entry), do: Map.get(entry, :type) || Map.get(entry, "type")

  defp exercise_level?(level), do: level in [:exercise, :variation]
end
