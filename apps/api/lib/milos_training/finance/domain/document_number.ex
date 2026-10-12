defmodule MilosTraining.Finance.Domain.DocumentNumber do
  @moduledoc """
  Gapless per-tenant document numbering (ADR-126).

  The infrastructure locks the tenant's counter row (`FOR UPDATE`) inside the
  issuing transaction, asks this module for the next value and writes it back
  before inserting the document. Because the counter and the document commit
  or roll back together, a failed issue never consumes a number.

  Refund receipt numbers are `RFD-` followed by the sequence padded to six
  digits (`RFD-000001`); sequences beyond 999999 simply grow wider.
  """

  @prefixes %{"refund_receipt" => "RFD"}
  @pad 6

  @doc "Document types that have a numbering scheme."
  def document_types, do: Map.keys(@prefixes)

  @doc "The value that follows the counter's current `last_value`."
  def next_sequence(last_value) when is_integer(last_value) and last_value >= 0,
    do: last_value + 1

  @doc "Formats a sequence for a document type."
  def format(document_type, sequence)
      when is_map_key(@prefixes, document_type) and is_integer(sequence) and sequence > 0 do
    Map.fetch!(@prefixes, document_type) <>
      "-" <> (sequence |> Integer.to_string() |> String.pad_leading(@pad, "0"))
  end

  @doc "Parses a formatted number back to `{document_type, sequence}`."
  def parse(number) when is_binary(number) do
    with [prefix, digits] <- String.split(number, "-", parts: 2),
         {document_type, _prefix} <- Enum.find(@prefixes, fn {_type, p} -> p == prefix end),
         {sequence, ""} when sequence > 0 <- Integer.parse(digits) do
      {:ok, {document_type, sequence}}
    else
      _ -> :error
    end
  end

  def parse(_number), do: :error

  @doc "True when the sequences are exactly 1..n with no gaps or duplicates."
  def gapless?(sequences) when is_list(sequences) do
    Enum.sort(sequences) == Enum.to_list(1..length(sequences)//1)
  end
end
