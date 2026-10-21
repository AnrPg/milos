defmodule Palee.Body.Domain.SettingsPolicy do
  @moduledoc """
  A person's body settings (ADR-158) and the opt-in measure reminder.

  - `units`: `metric` (default) or `imperial`; values are stored in SI.
  - `weight_display`: `number` (default), `trend` or `hidden` (`DisplayPolicy`).
  - `journal_sections`: `body`, `wellness`, `cravings`, each on or off
    (vision §8.6: every section can be switched off entirely).
  - `measure_reminder_weeks`: 1–12, or `nil` (off, the default).
  - `default_visibility`: the visibility of the last snapshot saved, which the
    next one starts from (`private` until then).
  - `blur_photos`: photos show blurred until tapped (default on).
  - `compare_mode`: `slider` (default) or `side_by_side`.
  - `felt_prompt_without_goals`: offer the «Τι ένιωσες;» step after a
    workout without goals, from the body (default on, ADR-163). Workouts
    with goals always offer it.
  """

  alias Palee.Body.Domain.{DisplayPolicy, MetricCatalog, SnapshotPolicy}

  @sections ~w(body wellness cravings)
  @compare_modes ~w(slider side_by_side)
  @max_reminder_weeks 12

  def sections, do: @sections
  def compare_modes, do: @compare_modes
  def max_reminder_weeks, do: @max_reminder_weeks

  def defaults do
    %{
      units: "metric",
      weight_display: "number",
      journal_sections: Map.new(@sections, &{&1, true}),
      measure_reminder_weeks: nil,
      default_visibility: "private",
      blur_photos: true,
      compare_mode: "slider",
      felt_prompt_without_goals: true,
      reminder_anchor_at: nil,
      last_reminded_at: nil
    }
  end

  @doc "Stored settings (or none) with every default filled."
  def effective(nil), do: defaults()

  def effective(stored) when is_map(stored) do
    defaults = defaults()

    defaults
    |> Map.merge(Map.take(stored, Map.keys(defaults)), fn
      :journal_sections, default, value when is_map(value) -> Map.merge(default, value)
      _key, default, nil -> default
      _key, _default, value -> value
    end)
    |> Map.put(:measure_reminder_weeks, Map.get(stored, :measure_reminder_weeks))
  end

  @doc """
  Validates a partial update (string or atom keys) against `current` and
  returns the changes to store. Turning the reminder on (or changing its
  interval) restarts its count from `now`.
  """
  def changes(current, params, %DateTime{} = now) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    with {:ok, acc} <- put_choice(%{}, params, "units", MetricCatalog.unit_systems()),
         {:ok, acc} <- put_choice(acc, params, "weight_display", DisplayPolicy.modes()),
         {:ok, acc} <-
           put_choice(acc, params, "default_visibility", SnapshotPolicy.visibilities()),
         {:ok, acc} <- put_choice(acc, params, "compare_mode", @compare_modes),
         {:ok, acc} <- put_boolean(acc, params, "blur_photos"),
         {:ok, acc} <- put_boolean(acc, params, "felt_prompt_without_goals"),
         {:ok, acc} <- put_sections(acc, current, params),
         {:ok, acc} <- put_reminder(acc, current, params, now) do
      {:ok, acc}
    end
  end

  defp put_choice(acc, params, key, allowed) do
    case Map.fetch(params, key) do
      :error -> {:ok, acc}
      {:ok, value} when is_binary(value) -> choice(acc, key, value, allowed)
      {:ok, _other} -> {:error, :invalid_body_settings, %{field: key}}
    end
  end

  defp choice(acc, key, value, allowed) do
    if value in allowed,
      do: {:ok, Map.put(acc, String.to_existing_atom(key), value)},
      else: {:error, :invalid_body_settings, %{field: key}}
  end

  defp put_boolean(acc, params, key) do
    case Map.fetch(params, key) do
      :error ->
        {:ok, acc}

      {:ok, value} when is_boolean(value) ->
        {:ok, Map.put(acc, String.to_existing_atom(key), value)}

      {:ok, _other} ->
        {:error, :invalid_body_settings, %{field: key}}
    end
  end

  defp put_sections(acc, current, params) do
    case Map.fetch(params, "journal_sections") do
      :error ->
        {:ok, acc}

      {:ok, sections} when is_map(sections) ->
        sections = Map.new(sections, fn {key, value} -> {to_string(key), value} end)

        if Enum.all?(sections, fn {key, value} -> key in @sections and is_boolean(value) end),
          do:
            {:ok, Map.put(acc, :journal_sections, Map.merge(current.journal_sections, sections))},
          else: {:error, :invalid_body_settings, %{field: "journal_sections"}}

      {:ok, _other} ->
        {:error, :invalid_body_settings, %{field: "journal_sections"}}
    end
  end

  defp put_reminder(acc, current, params, now) do
    case Map.fetch(params, "measure_reminder_weeks") do
      :error ->
        {:ok, acc}

      {:ok, nil} ->
        {:ok, Map.merge(acc, %{measure_reminder_weeks: nil, reminder_anchor_at: nil})}

      {:ok, weeks} when is_integer(weeks) and weeks >= 1 and weeks <= @max_reminder_weeks ->
        anchor =
          if weeks == current.measure_reminder_weeks,
            do: current.reminder_anchor_at || now,
            else: now

        {:ok, Map.merge(acc, %{measure_reminder_weeks: weeks, reminder_anchor_at: anchor})}

      {:ok, _other} ->
        {:error, :invalid_body_settings, %{field: "measure_reminder_weeks"}}
    end
  end

  @doc "Whether a section of the journal is on."
  def section_on?(settings, section) when section in @sections,
    do: Map.get(settings.journal_sections, section, true) != false

  @doc """
  Whether a measure reminder is due at `now`: the reminder is on and N weeks
  have passed since the later of the last snapshot, the last reminder and
  the moment it was turned on. The SQL twin is `palee_body_reminders_due`.
  """
  def reminder_due?(%{measure_reminder_weeks: nil}, _last_taken_at, _now), do: false

  def reminder_due?(%{measure_reminder_weeks: weeks} = settings, last_taken_at, now)
      when is_integer(weeks) do
    reference =
      [settings.reminder_anchor_at, settings.last_reminded_at, last_taken_at]
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime, fn -> nil end)

    case reference do
      nil -> false
      at -> DateTime.compare(DateTime.add(at, weeks * 7 * 86_400, :second), now) != :gt
    end
  end

  @doc "Holds a reminder to one per person per day, even when a job retries."
  def reminder_dedupe_key(user_id, %Date{} = day), do: "body_measure_reminder:#{user_id}:#{day}"
end
