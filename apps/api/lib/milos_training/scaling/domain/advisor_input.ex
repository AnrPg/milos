defmodule MilosTraining.Scaling.Domain.AdvisorInput do
  @moduledoc """
  What the scaling advisor is told (ADR-174), pure.

  Data minimisation: the programmed workout (titles, movements and their
  prescription), the athlete's active injuries **with the gym's provenance**
  (body area, severity, restriction tags, the training limitations text; never
  a personal self-report, never a name or an id of the athlete), the movements
  the deterministic injury policy (ADR-124) already flags, the gym's scale
  levels and the changes a coach approved for this athlete before.

  Movements keep the workout's own section and exercise ids, so every change
  the advisor proposes can become an ADR-050 patch on a concrete row.
  """

  @max_history 10
  @max_text 300

  @doc """
  Builds the advisor input from `%{workout, injuries, warnings, scale_levels,
  history, locale}`.
  """
  def build(%{workout: workout} = params) do
    %{
      locale: Map.get(params, :locale) || "el",
      workout: %{
        title: text(field(workout, :title), 120),
        type: field(workout, :type) && to_string(field(workout, :type)),
        sections: sections(workout)
      },
      injuries: params |> Map.get(:injuries, []) |> Enum.map(&injury/1),
      flagged_movements: params |> Map.get(:warnings, []) |> flagged(),
      scale_levels:
        params
        |> Map.get(:scale_levels, [])
        |> Enum.map(&%{slug: field(&1, :slug), label: field(&1, :label)}),
      approved_before: params |> Map.get(:history, []) |> Enum.take(@max_history)
    }
  end

  @doc """
  The movements of a normalized workout: `%{id, section_id, section_name,
  name, prescription}`. A free-text workout without sections reads its body
  line by line under one `free-text` section, with `line-N` ids.
  """
  def movements(workout) do
    workout |> sections() |> Enum.flat_map(fn section -> section.movements end)
  end

  defp sections(workout) do
    case field(workout, :sections) do
      [_ | _] = sections -> sections |> Enum.map(&section/1) |> Enum.reject(&(&1.movements == []))
      _none -> free_text_section(field(workout, :free_text_body))
    end
  end

  defp section(section) do
    section_id = to_string(field(section, :id))
    section_name = text(field(section, :name), 80)

    movements =
      (field(section, :exercises) || [])
      |> Enum.reject(&(to_string(field(&1, :item_type) || "exercise") == "header"))
      |> Enum.filter(&is_binary(field(&1, :name)))
      |> Enum.map(fn exercise ->
        %{
          id: to_string(field(exercise, :id)),
          section_id: section_id,
          section_name: section_name,
          name: text(field(exercise, :name), 80),
          prescription: prescription(exercise)
        }
      end)

    %{id: section_id, name: section_name, movements: movements}
  end

  defp free_text_section(body) when is_binary(body) do
    movements =
      body
      |> String.split(["\r\n", "\n"])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(40)
      |> Enum.with_index(1)
      |> Enum.map(fn {line, index} ->
        %{
          id: "line-#{index}",
          section_id: "free-text",
          section_name: nil,
          name: text(line, 120),
          prescription: nil
        }
      end)

    if movements == [], do: [], else: [%{id: "free-text", name: nil, movements: movements}]
  end

  defp free_text_section(_body), do: []

  defp prescription(exercise) do
    sets = field(exercise, :sets)
    value = field(exercise, :prescription_value)
    unit = field(exercise, :prescription_unit)
    load = field(exercise, :load_value)
    load_mode = field(exercise, :load_mode)

    [
      sets && "#{sets} sets",
      value && Enum.join(Enum.reject([value, unit], &is_nil/1), " "),
      load && Enum.join(Enum.reject([load, load_mode], &is_nil/1), " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp injury(injury) do
    %{
      body_area: text(field(injury, :body_area), 80),
      severity: field(injury, :severity),
      tags: List.wrap(field(injury, :tags)),
      training_limitations: text(field(injury, :training_limitations), @max_text)
    }
  end

  defp flagged(warnings) do
    warnings
    |> Enum.flat_map(&List.wrap(field(&1, :exercises)))
    |> Enum.group_by(&field(&1, :name))
    |> Enum.map(fn {name, entries} ->
      level = if Enum.any?(entries, &(field(&1, :level) == :avoid)), do: "avoid", else: "caution"
      %{name: name, level: level}
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  The body regions behind the warnings, for the coach's queue (no free text).
  """
  def regions(warnings) do
    warnings
    |> Enum.flat_map(&List.wrap(field(&1, :regions)))
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  @doc """
  A stable fingerprint of what the advisor would be asked, without the
  history (which changes only through this feature): when it changes, a
  pending suggestion is stale.
  """
  def digest(input) do
    input
    |> Map.delete(:approved_before)
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(%{} = map),
    do: map |> Enum.map(fn {key, value} -> [to_string(key), canonical(value)] end) |> Enum.sort()

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value

  defp text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max)
    end
  end

  defp text(_value, _max), do: nil

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_map, _key), do: nil
end
