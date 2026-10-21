defmodule Palee.Identity.RegistrationPolicy do
  @moduledoc false

  @roles [:member, :athlete, :admin]
  @self_register_roles [:member, :athlete]

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
    String.length(password) >= 4
  end

  def valid_password?(_password), do: false

  defp transliterate(value), do: Palee.Transliteration.latin(value)
end
