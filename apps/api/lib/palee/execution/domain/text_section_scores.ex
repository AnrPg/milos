defmodule Palee.Execution.Domain.TextSectionScores do
  @moduledoc """
  The athlete's results for the scores a coach set on text sections
  (ADR-179), pure.

  Each entry names a section and one of its metrics (`metric_key`) and
  carries a number (time in seconds). It becomes an ordinary section score
  with its own `section_key` (`<section id>:<metric key>`), so progress
  history, the coach's drill-down, training history and the journal show it
  next to structured scores, one series per metric.

  Entries without a value are skipped (a field left blank); an entry for an
  unknown section or metric, a duplicate or a value that is not a
  non-negative number is an error, so a stale client cannot store garbage.
  """

  @max_value 1_000_000_000

  @doc "`{:ok, section_scores}` or `{:error, :bad_request}`."
  def normalize(entries, sections) when is_list(entries) and is_list(sections) do
    metrics = metrics_by_key(sections)

    entries
    |> Enum.reject(&blank?(value(&1, :value)))
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn entry, {:ok, acc, seen} ->
      key = {value(entry, :section_id), value(entry, :metric_key)}

      with false <- MapSet.member?(seen, key),
           {section, metric} <- Map.get(metrics, key),
           {:ok, number} <- number(value(entry, :value)) do
        {:cont, {:ok, [score(section, metric, number) | acc], MapSet.put(seen, key)}}
      else
        _invalid -> {:halt, {:error, :bad_request}}
      end
    end)
    |> case do
      {:ok, scores, _seen} -> {:ok, Enum.reverse(scores)}
      error -> error
    end
  end

  def normalize(nil, _sections), do: {:ok, []}
  def normalize(_entries, _sections), do: {:error, :bad_request}

  @doc """
  The scores a coach set on a sectioned workout, in order, each shaped like
  a scored section (`id`, `section_key`, `name`, `score_type`, `unit`) so
  rankings can use one.
  """
  def section_metrics(%{authoring_mode: "sectioned_text", sections: sections})
      when is_list(sections) do
    sections
    |> Enum.sort_by(&(value(&1, :order) || 0))
    |> Enum.flat_map(fn section ->
      section
      |> value(:score_config)
      |> metrics()
      |> Enum.map(fn metric ->
        %{
          id: value(section, :id),
          section_key: "#{value(section, :id)}:#{value(metric, :key)}",
          name: "#{section_title(section)} · #{value(metric, :label)}",
          score_type: value(metric, :kind),
          unit: value(metric, :unit)
        }
      end)
    end)
  end

  def section_metrics(_workout), do: []

  defp metrics_by_key(sections) do
    for section <- sections,
        metric <- metrics(value(section, :score_config)),
        into: %{} do
      {{value(section, :id), value(metric, :key)}, {section, metric}}
    end
  end

  defp metrics(%{} = config) do
    case value(config, :metrics) do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _none -> []
    end
  end

  defp metrics(_config), do: []

  defp score(section, metric, number) do
    section_id = value(section, :id)

    %{
      "section_id" => section_id,
      "section_key" => "#{section_id}:#{value(metric, :key)}",
      "section_name" => "#{section_title(section)} · #{value(metric, :label)}",
      "metric_key" => value(metric, :key),
      "metric_label" => value(metric, :label),
      "value" => number,
      "unit" => value(metric, :unit),
      "score_type" => value(metric, :kind),
      "source" => "user",
      "kind" => "final"
    }
  end

  defp section_title(section) do
    untitled = get_in(value(section, :section_metadata) || %{}, ["untitled"]) == true
    if untitled, do: "##{value(section, :order)}", else: value(section, :name)
  end

  defp number(value) when is_integer(value) and value >= 0 and value <= @max_value,
    do: {:ok, value}

  defp number(value) when is_float(value) and value >= 0 and value <= @max_value,
    do: {:ok, Float.round(value, 3)}

  defp number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> parsed |> normalize_float() |> number()
      _other -> :error
    end
  end

  defp number(_value), do: :error

  defp normalize_float(float) when float == trunc(float), do: trunc(float)
  defp normalize_float(float), do: float

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_map, _key), do: nil
end
