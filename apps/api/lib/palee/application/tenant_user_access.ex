defmodule Palee.Application.TenantUserAccess do
  @moduledoc false

  alias Palee.{Identity, Organizations}
  alias Palee.Organizations.TenantContext

  def list_active_users(%TenantContext{} = context) do
    context
    |> Organizations.list_active_membership_user_ids()
    |> Identity.list_by_ids()
  end

  def list_active_users(_context), do: []

  def fetch_active_user(%TenantContext{} = context, user_id) when is_binary(user_id) do
    active_user_ids =
      context
      |> Organizations.list_active_membership_user_ids()
      |> MapSet.new()

    if MapSet.member?(active_user_ids, user_id) do
      case Identity.find_by_id(user_id) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    else
      {:error, :not_found}
    end
  end

  def fetch_active_user(%TenantContext{}, _user_id), do: {:error, :not_found}
  def fetch_active_user(_context, _user_id), do: {:error, :organization_context_required}

  @doc """
  ADR-217: the person's role set in the caller's gym (atoms, privilege order),
  `[]` when they hold none. Profiles read these, never `users.role`.
  """
  def tenant_roles(%{organization_id: organization_id}, user_id)
      when is_binary(organization_id) and is_binary(user_id) do
    case Organizations.membership_summary(organization_id, user_id) do
      %{roles: roles} -> Enum.map(roles, &String.to_existing_atom/1)
      nil -> []
    end
  end

  def tenant_roles(_context, _user_id), do: []
end
