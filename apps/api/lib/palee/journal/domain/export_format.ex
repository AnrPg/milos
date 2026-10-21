defmodule Palee.Journal.Domain.ExportFormat do
  @moduledoc """
  The files of a whole-journal export (ADR-162, board 17 extra «Εξαγωγή»):
  `journal.json` (every entry across providers with its source label, in
  the shape the feed returns) and `training.csv` (one row per workout done
  or logged, for spreadsheets).
  """

  @csv_header ~w(date kind source provider former title workout_type duration_seconds scale scores visibility)
  @training_kinds ~w(execution training_log)

  @doc "Plain JSON-safe data: structs become maps, Ecto metadata and unloaded associations go."
  def plain(%DateTime{} = value), do: value
  def plain(%NaiveDateTime{} = value), do: value
  def plain(%Date{} = value), do: value
  def plain(%Time{} = value), do: value
  def plain(%Decimal{} = value), do: Decimal.to_string(value)
  def plain(%{__struct__: Ecto.Association.NotLoaded}), do: nil

  def plain(%{__struct__: _struct} = value),
    do: value |> Map.from_struct() |> Map.delete(:__meta__) |> plain()

  def plain(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, plain(v)} end)
  def plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  def plain(value) when is_tuple(value), do: value |> Tuple.to_list() |> plain()
  def plain(value), do: value

  @doc "The JSON document."
  def json(items, providers, exported_at) do
    %{
      format: "palee.journal.v1",
      exported_at: exported_at,
      providers: plain(providers),
      entries: plain(items)
    }
    |> Jason.encode!(pretty: true)
  end

  @doc "The training CSV (RFC 4180, CRLF line ends)."
  def training_csv(items) do
    rows =
      items
      |> Enum.filter(&(&1.kind in @training_kinds))
      |> Enum.map(&row/1)

    [@csv_header | rows]
    |> Enum.map_join("", fn row -> Enum.map_join(row, ",", &cell/1) <> "\r\n" end)
  end

  defp row(item) do
    entry = item.entry
    source = Map.get(item, :source) || %{}

    [
      DateTime.to_iso8601(item.occurred_at),
      item.kind,
      Map.get(source, :kind),
      Map.get(source, :name),
      Map.get(source, :former, false),
      Map.get(entry, :workout_title) || Map.get(entry, :title),
      Map.get(entry, :workout_type),
      duration(item.kind, entry),
      Map.get(entry, :scale_level_slug),
      scores(Map.get(entry, :section_scores)),
      item.journal_visibility
    ]
  end

  defp duration("execution", entry), do: div(Map.get(entry, :total_elapsed_ms) || 0, 1000)
  defp duration(_kind, entry), do: Map.get(entry, :duration_seconds)

  defp scores(scores) do
    scores
    |> List.wrap()
    |> Enum.map_join("; ", fn score ->
      name = field(score, :section_name)
      value = "#{field(score, :value)}#{unit(field(score, :unit))}"
      if name, do: "#{name}: #{value}", else: value
    end)
  end

  defp unit(nil), do: ""
  defp unit(unit), do: " #{unit}"

  defp field(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp cell(nil), do: ""

  defp cell(value) do
    text = to_string(value)

    if String.contains?(text, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end
end
