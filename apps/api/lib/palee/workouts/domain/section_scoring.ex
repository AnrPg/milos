defmodule Palee.Workouts.Domain.SectionScoring do
  @moduledoc """
  How a text section is scored (ADR-180), pure.

  A coach may say what a section counts («This section is scored by»): one
  or more metrics, each from the common paradigms below or a custom one with
  the coach's own name. After the workout the athlete fills one field per
  metric, and each result is stored as a section score of its own (keyed by
  section and metric), so progress, history and the coach's views read it
  like any structured score.

  Stored in the section's `score_config` as `%{"metrics" => [metric]}`, a
  metric being `%{"key", "label", "kind", "unit"}`. Every value is a number
  (time in seconds), so results stay comparable over time.
  """

  @kinds %{
    "rounds" => "rounds",
    "reps" => "reps",
    "time" => "s",
    "load" => "kg",
    "calories" => "kcal",
    "distance" => "m",
    "custom" => nil
  }
  @max_metrics 6
  @max_label_length 40

  def kinds, do: Map.keys(@kinds)
  def max_metrics, do: @max_metrics

  @doc "The unit a metric kind is recorded in (nil for custom metrics)."
  def unit(kind), do: Map.get(@kinds, kind)

  @doc """
  Normalises a section's scoring: `{:ok, score_config | nil}` or
  `{:error, :scoring_invalid}`. Accepts `%{"metrics" => [...]}` or the list
  itself; each metric needs a label (1–#{@max_label_length} characters) and a
  known kind, and two metrics of a section cannot share a key.
  """
  def normalize(nil), do: {:ok, nil}
  def normalize(%{} = config), do: config |> value(:metrics) |> normalize()
  def normalize([]), do: {:ok, nil}

  def normalize(metrics) when is_list(metrics) and length(metrics) <= @max_metrics do
    normalized = Enum.map(metrics, &metric/1)
    keys = Enum.map(normalized, &(&1 && &1["key"]))

    if Enum.all?(normalized) and length(Enum.uniq(keys)) == length(keys),
      do: {:ok, %{"metrics" => normalized}},
      else: {:error, :scoring_invalid}
  end

  def normalize(_metrics), do: {:error, :scoring_invalid}

  @doc "A section's metrics from its stored `score_config` ([] when it is not scored)."
  def metrics(%{} = score_config) do
    case value(score_config, :metrics) do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _none -> []
    end
  end

  def metrics(_score_config), do: []

  defp metric(%{} = raw) do
    label = raw |> value(:label) |> trimmed()
    kind = value(raw, :kind) || "custom"

    if label != "" and String.length(label) <= @max_label_length and Map.has_key?(@kinds, kind) do
      %{"key" => key(kind, label), "label" => label, "kind" => kind, "unit" => unit(kind)}
    end
  end

  defp metric(_raw), do: nil

  # Keyed by the coach's name for it, so a section may count two things of
  # one kind («Thrusters» and «Pull-ups», both reps).
  defp key(kind, label) do
    case slug(label) do
      "" -> kind
      slug -> slug
    end
  end

  defp slug(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
    |> String.trim("-")
  end

  defp trimmed(text) when is_binary(text), do: String.trim(text)
  defp trimmed(_text), do: ""

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
