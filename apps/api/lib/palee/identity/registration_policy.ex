defmodule Palee.Identity.RegistrationPolicy do
  @moduledoc false

  alias Palee.Identity.Domain.Handle

  @roles [:member, :athlete, :admin]
  @self_register_roles [:member, :athlete]

  def roles, do: @roles
  def self_register_roles, do: @self_register_roles

  @doc "The @handle form of typed text (ADR-187); kept under its old name for callers."
  def normalize_nickname(nickname), do: Handle.normalize(nickname)

  def valid_nickname?(nickname), do: Handle.valid?(nickname)

  def valid_password?(password) when is_binary(password) do
    String.length(password) >= 4
  end

  def valid_password?(_password), do: false
end
