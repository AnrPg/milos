defmodule Palee.BusinessAccounts.Domain.ActivationLinkPolicy do
  @moduledoc """
  ADR-184: the rules of a business activation link.

  A vendor issues it for **one existing account** and **one role** (owner or
  admin) of one demo business. It is single-use, expires (7 days by default,
  at most 30) and a new link for the same business replaces the live one.
  Opening it while signed in as that account activates the business and gives
  the account the role, keeping the roles it already holds.
  """

  @roles ~w(owner admin)
  @default_lifetime_seconds 7 * 24 * 3600
  @max_lifetime_seconds 30 * 24 * 3600
  @entropy_bytes 32
  @maximum_encoded_bytes 256

  def roles, do: @roles
  def default_lifetime_seconds, do: @default_lifetime_seconds

  @doc "A new random token (only its digest is stored)."
  def generate_token do
    @entropy_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def digest(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc "The digest of a token a person brings, or `:invalid_activation_link`."
  def decode(token)
      when is_binary(token) and byte_size(token) >= 20 and
             byte_size(token) <= @maximum_encoded_bytes,
      do: {:ok, digest(token)}

  def decode(_token), do: {:error, :invalid_activation_link}

  @doc "The web path that opens a link."
  def path(token), do: "/activate-business?token=" <> token

  @doc """
  Validates what a vendor asks for: a role and an optional lifetime in
  seconds (one hour to 30 days).
  """
  def normalize_issue(params) do
    role = value(params, :role) || "owner"
    lifetime = value(params, :lifetime_seconds) || @default_lifetime_seconds

    cond do
      role not in @roles -> {:error, :invalid_activation_role}
      not is_integer(lifetime) -> {:error, :invalid_activation_lifetime}
      lifetime < 3600 or lifetime > @max_lifetime_seconds -> {:error, :invalid_activation_lifetime}
      true -> {:ok, %{role: role, lifetime_seconds: lifetime}}
    end
  end

  @doc "`:live`, `:expired`, `:redeemed` or `:revoked` at `now`."
  def state(%{redeemed_at: %DateTime{}}, _now), do: :redeemed
  def state(%{revoked_at: %DateTime{}}, _now), do: :revoked

  def state(%{expires_at: %DateTime{} = expires_at}, now) do
    if DateTime.compare(expires_at, now) == :gt, do: :live, else: :expired
  end

  @doc """
  The role set the account holds after activation: what it had, plus the
  role the link grants, plus `coach` in an independent coach's practice (the
  practice is the coach, ADR-170).
  """
  def roles_after(existing_roles, role, provider_kind) do
    granted = [String.to_existing_atom(role) | if(provider_kind == "coach", do: [:coach], else: [])]
    Enum.uniq((existing_roles || []) ++ granted)
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
