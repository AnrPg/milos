defmodule MilosTraining.Application.TenantUserAccess do
  @moduledoc false

  alias MilosTraining.{Identity, Organizations}
  alias MilosTraining.Organizations.TenantContext

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
end
