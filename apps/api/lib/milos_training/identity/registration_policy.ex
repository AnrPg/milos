defmodule MilosTraining.Identity.RegistrationPolicy do
  @moduledoc false

  @roles [:member, :athlete, :admin]
  @self_register_roles [:member, :athlete]

  def roles, do: @roles
  def self_register_roles, do: @self_register_roles

  def normalize_nickname(nil), do: nil

  def normalize_nickname(nickname) when is_binary(nickname) do
    nickname
    |> String.trim()
    |> String.downcase()
  end
end
