defmodule Palee.Finance.Domain.PackageCode do
  @moduledoc """
  Derives stable package codes from names (ADR-096).

  Greek text is transliterated with ELOT 743 conventions before the code is
  reduced to lowercase ASCII words joined by underscores, so Greek package
  names never collapse into an empty code.
  """

  @digraphs [
    {"ου", "ou"},
    {"αυ", "av"},
    {"ευ", "ev"},
    {"ηυ", "iv"},
    {"γγ", "ng"},
    {"γκ", "gk"},
    {"γξ", "nx"},
    {"γχ", "nch"},
    {"μπ", "mp"},
    {"ντ", "nt"}
  ]

  @letters %{
    "α" => "a",
    "β" => "v",
    "γ" => "g",
    "δ" => "d",
    "ε" => "e",
    "ζ" => "z",
    "η" => "i",
    "θ" => "th",
    "ι" => "i",
    "κ" => "k",
    "λ" => "l",
    "μ" => "m",
    "ν" => "n",
    "ξ" => "x",
    "ο" => "o",
    "π" => "p",
    "ρ" => "r",
    "σ" => "s",
    "ς" => "s",
    "τ" => "t",
    "υ" => "y",
    "φ" => "f",
    "χ" => "ch",
    "ψ" => "ps",
    "ω" => "o"
  }

  @max_length 60

  @doc "Normalized code for a name or explicit code, or nil when nothing usable remains."
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> strip_diacritics()
    |> transliterate()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> String.slice(0, @max_length)
    |> String.trim("_")
    |> case do
      "" -> nil
      code -> code
    end
  end

  def normalize(_), do: nil

  @doc "First code based on `base` that is not in `taken` (`base`, `base_2`, `base_3`, ...)."
  def unique(base, taken) when is_binary(base) do
    taken = MapSet.new(taken)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> String.slice(base, 0, @max_length - String.length("_#{n}")) <> "_#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  defp strip_diacritics(value) do
    value
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  defp transliterate(value) do
    value = Enum.reduce(@digraphs, value, fn {from, to}, acc -> String.replace(acc, from, to) end)

    value
    |> String.graphemes()
    |> Enum.map_join(&Map.get(@letters, &1, &1))
  end
end
