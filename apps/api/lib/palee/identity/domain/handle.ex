defmodule Palee.Identity.Domain.Handle do
  @moduledoc """
  ADR-187: the unique @handle of a profile.

  Stored lowercase ASCII only (a-z, 0-9, `.`, `_`), the strictest
  anti-spoofing level of Unicode UTS #39: no look-alike letters from another
  script can pose as someone else's handle. What a person types is folded
  first (case, accents, Greek and Cyrillic transliterated), so "Τολάρας",
  "Tolaras" and "tolaras" are the same handle. Pure.
  """

  @min 3
  @max 30

  def min_length, do: @min
  def max_length, do: @max

  @doc "Folds typed text to its handle form. Characters with no Latin form are dropped."
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("@")
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{M}/u, "")
    |> Palee.Transliteration.latin()
    |> String.replace(~r/[^a-z0-9._]/, "")
  end

  @doc """
  True when the typed value folds to a well-formed handle without losing any
  character: letters (any script with a Latin form), digits, `.` and `_` only.
  """
  def valid?(value) when is_binary(value) do
    trimmed = value |> String.trim() |> String.trim_leading("@")
    normalized = normalize(trimmed)

    Regex.match?(~r/^[\p{L}\p{M}0-9._]+$/u, trimmed) and
      normalized_length_kept?(trimmed, normalized) and well_formed?(normalized)
  end

  def valid?(_value), do: false

  @doc "A stored handle (already normalized) that satisfies every rule."
  def well_formed?(handle) when is_binary(handle) do
    String.length(handle) in @min..@max and
      Regex.match?(~r/^[a-z0-9._]+$/, handle) and
      not String.starts_with?(handle, ".") and
      not String.ends_with?(handle, ".") and
      not String.contains?(handle, "..")
  end

  def well_formed?(_handle), do: false

  @doc """
  A handle suggested from a display name: folded, spaces and dashes become
  `_`, trimmed to the length limits. Returns nil when the name has no Latin
  form at all (e.g. Chinese), so the person types one instead.
  """
  def suggest(display_name) when is_binary(display_name) do
    candidate =
      display_name
      |> String.replace(~r/[\s\-]+/u, "_")
      |> normalize()
      |> String.replace(~r/\.{2,}/, ".")
      |> String.replace(~r/_{2,}/, "_")
      |> String.trim(".")
      |> String.trim("_")
      |> String.slice(0, @max)
      |> String.trim(".")

    if well_formed?(candidate), do: candidate, else: nil
  end

  def suggest(_display_name), do: nil

  @doc "Alternatives for a taken handle: `name_24`, `name.fit`, ... (well-formed only)."
  def alternatives(handle, count \\ 3) when is_binary(handle) do
    base = String.slice(handle, 0, @max - 4)

    Stream.repeatedly(fn -> "#{base}_#{:rand.uniform(98) + 1}" end)
    |> Stream.filter(&well_formed?/1)
    |> Stream.uniq()
    |> Enum.take(count)
  end

  # A letter may expand ("θ" -> "th") or fold ("é" -> "e") but must never
  # vanish: a character with no Latin form makes the typed handle invalid
  # instead of silently becoming a different one.
  defp normalized_length_kept?(trimmed, normalized) do
    trimmed
    |> String.graphemes()
    |> Enum.all?(fn grapheme -> normalize(grapheme) != "" end) and normalized != ""
  end
end
