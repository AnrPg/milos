defmodule Palee.Application.DeleteOrganization do
  @moduledoc """
  Deletes an organization outright. As a safety net the vendor must have
  exported its data first (the purge workflow's export step); the reviewed
  purge (`ExecuteOrganizationPurge`) is the full path that also archives
  retained records.
  """

  alias Palee.{Identity, Organizations}

  def call(platform_context, organization_id) do
    with :ok <- require_export(platform_context, organization_id),
         {:ok, user_ids} <-
           Organizations.list_deletable_organization_user_ids(platform_context, organization_id),
         {:ok, organization} <-
           Organizations.delete_organization(platform_context, organization_id),
         :ok <- delete_users(user_ids) do
      {:ok, organization}
    end
  end

  defp require_export(platform_context, organization_id) do
    case Organizations.get_organization_purge(platform_context, organization_id) do
      {:ok, %{export_completed_at: %DateTime{}}} -> :ok
      _none -> {:error, :organization_export_required}
    end
  end

  # Accounts go after the organization row, so its own records no longer hold
  # them. An account another organization's records still need is kept.
  defp delete_users(user_ids) do
    Enum.reduce_while(user_ids, :ok, fn user_id, :ok ->
      case Identity.find_by_id(user_id) do
        nil ->
          {:cont, :ok}

        user ->
          case Identity.delete_tenant_scoped_user(user) do
            :ok -> {:cont, :ok}
            {:error, {:user_has_restricted_history, _record}} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end
end
