defmodule MilosTraining.Finance.Domain.InvoiceNumber do
  @moduledoc false

  @default_segment "MANUAL"
  @max_segment_length 12

  def format(sequence, issued_at, package_code \\ nil)
      when is_integer(sequence) and sequence > 0 do
    "INV-" <>
      pad_sequence(sequence) <>
      "-" <>
      package_segment(package_code) <>
      "-" <>
      timestamp_segment(issued_at)
  end

  def package_segment(nil), do: @default_segment

  def package_segment(package_code) when is_binary(package_code) do
    package_code
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]+/u, "")
    |> case do
      "" -> @default_segment
      sanitized -> String.slice(sanitized, 0, @max_segment_length)
    end
  end

  def package_segment(_other), do: @default_segment

  defp pad_sequence(sequence) do
    sequence
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp timestamp_segment(%DateTime{} = issued_at) do
    issued_at
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp timestamp_segment(%NaiveDateTime{} = issued_at) do
    issued_at
    |> DateTime.from_naive!("Etc/UTC")
    |> timestamp_segment()
  end
end
