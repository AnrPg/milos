defmodule MilosTraining.Transliteration do
  @moduledoc """
  Greek and Cyrillic lower-case letters to Latin, for identifiers people
  type in their own script: nicknames (Identity) and organization slugs
  (Organizations, ADR-170). Pure; callers lower-case and strip accents first.
  """

  @latin %{
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
    "ω" => "o",
    "а" => "a",
    "б" => "b",
    "в" => "v",
    "г" => "g",
    "д" => "d",
    "е" => "e",
    "ё" => "e",
    "ж" => "zh",
    "з" => "z",
    "и" => "i",
    "й" => "i",
    "к" => "k",
    "л" => "l",
    "м" => "m",
    "н" => "n",
    "о" => "o",
    "п" => "p",
    "р" => "r",
    "с" => "s",
    "т" => "t",
    "у" => "u",
    "ф" => "f",
    "х" => "h",
    "ц" => "ts",
    "ч" => "ch",
    "ш" => "sh",
    "щ" => "sht",
    "ъ" => "a",
    "ь" => "",
    "ю" => "yu",
    "я" => "ya"
  }

  @doc "Replaces every known Greek or Cyrillic letter; anything else is kept."
  def latin(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.map_join(&Map.get(@latin, &1, &1))
  end
end
