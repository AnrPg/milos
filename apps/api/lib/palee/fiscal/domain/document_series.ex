defmodule Palee.Fiscal.Domain.DocumentSeries do
  @moduledoc """
  Series and numbers of fiscal documents (ADR-241).

  One gapless sequence per organization and series. The series is the
  kind's prefix followed by the branch code when it is not 0 (`R`, `I`,
  `C`; `R1` for branch 1). The printed number is the series, a dash and the
  sequence padded to six digits (`R-000042`, `R1-000042`); longer sequences
  simply grow wider. Series and sequence are also kept apart because myDATA
  sends them as separate fields.
  """

  @prefixes %{"receipt" => "R", "invoice" => "I", "credit_note" => "C"}
  @pad 6

  def kinds, do: Map.keys(@prefixes)

  @doc "The series a document of `kind` from `branch_code` is numbered in."
  def series(kind, branch_code \\ 0)

  def series(kind, 0) when is_map_key(@prefixes, kind), do: Map.fetch!(@prefixes, kind)

  def series(kind, branch_code)
      when is_map_key(@prefixes, kind) and is_integer(branch_code) and branch_code > 0,
      do: Map.fetch!(@prefixes, kind) <> Integer.to_string(branch_code)

  @doc "The value that follows `last_value`."
  def next_sequence(last_value) when is_integer(last_value) and last_value >= 0,
    do: last_value + 1

  @doc "The printed number of `sequence` in `series`."
  def format(series, sequence) when is_binary(series) and is_integer(sequence) and sequence > 0,
    do: series <> "-" <> (sequence |> Integer.to_string() |> String.pad_leading(@pad, "0"))

  @doc "True when the sequences are exactly 1..n."
  def gapless?(sequences), do: Enum.sort(sequences) == Enum.to_list(1..length(sequences)//1)
end
