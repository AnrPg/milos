defmodule Palee.Organizations.Domain.JoinLinkPolicy do
  @moduledoc """
  Rules for the organization's public join link (`/join/<slug>`).

  The link is an opt-in, organization-wide alternative to one-time
  invitations: while enabled, anyone holding the organization's address can
  create an account (or use an existing one) and becomes a client with the
  configured role. It can only ever grant client roles; staff still need a
  one-time invitation. It is stored under `organization_settings.settings`.
  """

  @settings_key "join_link"
  @client_roles ~w(member athlete)
  @default %{"enabled" => false, "role" => "member"}

  def settings_key, do: @settings_key
  def client_roles, do: @client_roles

  @doc "Reads the join link from an organization settings map, with defaults."
  def from_settings(settings) when is_map(settings) do
    case Map.get(settings, @settings_key) do
      %{} = stored ->
        %{
          "enabled" => Map.get(stored, "enabled") == true,
          "role" =>
            if(Map.get(stored, "role") in @client_roles, do: stored["role"], else: "member")
        }

      _missing ->
        @default
    end
  end

  def from_settings(_settings), do: @default

  @doc "Validates an admin update, merging it over the current join link."
  def update(current, params) when is_map(current) and is_map(params) do
    enabled = value(params, :enabled, current["enabled"])
    role = value(params, :role, current["role"])

    cond do
      not is_boolean(enabled) -> {:error, :invalid_join_link}
      role not in @client_roles -> {:error, :invalid_join_link}
      true -> {:ok, %{"enabled" => enabled, "role" => role}}
    end
  end

  def update(_current, _params), do: {:error, :invalid_join_link}

  @doc "Whether a visitor can join an organization through its public link."
  def joinable?(join_link, organization_status) do
    organization_status == :active and Map.get(join_link, "enabled") == true
  end

  @doc """
  Decides what joining means for an account that may already belong to the
  organization. An active membership is left untouched (joining is
  idempotent); a suspended or removed one is never reactivated by a public
  link.
  """
  def join_decision(nil), do: :create
  def join_decision(%{status: :active}), do: :already_member
  def join_decision(_membership), do: {:error, :membership_unavailable}

  defp value(params, key, default) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, Atom.to_string(key), default)
    end
  end
end
