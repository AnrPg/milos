defmodule MilosTraining.Identity.RegistrationPolicy do
  @moduledoc false

  @roles [:member, :athlete, :admin]
  @self_register_roles [:member, :athlete]
  @transliterations %{
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

  def roles, do: @roles
  def self_register_roles, do: @self_register_roles

  def normalize_nickname(nil), do: nil

  def normalize_nickname(nickname) when is_binary(nickname) do
    nickname
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{M}/u, "")
    |> transliterate()
  end

  def valid_nickname?(nickname) when is_binary(nickname) do
    String.length(nickname) in 3..30 and Regex.match?(~r/^[\p{L}0-9_]+$/u, nickname) and
      Regex.match?(~r/^[a-z0-9_]+$/, normalize_nickname(nickname))
  end

  def valid_nickname?(_nickname), do: false

  def valid_password?(password) when is_binary(password) do
    String.length(password) >= 4 and not Regex.match?(~r/\s/u, password)
  end

  def valid_password?(_password), do: false

  defp transliterate(value) do
    value
    |> String.graphemes()
    |> Enum.map_join(&Map.get(@transliterations, &1, &1))
  end
end
