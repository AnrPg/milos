defmodule MilosTraining.Application.ExecuteOrganizationPurge do
  @moduledoc """
  ADR-099 stage 5. Purges an approved tenant in dependency order:

  1. each bounded context through its own `purge_tenant_data/1`, dependents
     first (Analytics ... Finance, Scheduling, Workouts);
  2. `identity` - tenant-only accounts (ADR-093) and their avatar objects;
  3. `storage` - tenant documents, except retained archives and documents a
     retaining context policy covers (e.g. Finance invoices);
  4. `organizations` - the organization row (cascading memberships, invitations,
     settings, domains, provisioning events) while the purge record is marked
     completed.

  Every finished step is recorded on the platform purge record before the next
  starts, so a retry skips completed steps and resumes where it failed. A
  completed purge is returned unchanged.
  """

  alias MilosTraining.{Identity, Organizations}
  alias MilosTraining.Application.{TenantDataContexts, TenantObjectStorage}
  alias MilosTraining.TenantData.Domain.RetentionReview

  def call(platform_context, purge_id) do
    case Organizations.get_organization_purge_by_id(platform_context, purge_id) do
      {:ok, %{status: :completed} = purge} -> {:ok, purge}
      {:ok, _purge} -> run(platform_context, purge_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run(platform_context, purge_id) do
    with {:ok, purge} <-
           Organizations.advance_organization_purge(platform_context, purge_id, :start_purge),
         {:ok, scope} <- Organizations.tenant_purge_context(platform_context, purge),
         {:ok, purge} <- purge_contexts(platform_context, purge, scope),
         {:ok, purge} <- purge_accounts(platform_context, purge),
         {:ok, purge} <- purge_objects(platform_context, purge) do
      Organizations.complete_organization_purge(platform_context, purge.id)
    else
      {:error, :invalid_purge_transition} = error ->
        error

      {:error, reason} ->
        _ =
          Organizations.advance_organization_purge(platform_context, purge_id, :fail, %{
            stage: "purge",
            reason: reason
          })

        {:error, reason}
    end
  end

  defp purge_contexts(platform_context, purge, scope) do
    Enum.reduce_while(TenantDataContexts.purge_sequence(), {:ok, purge}, fn {module, policy},
                                                                            {:ok, purge} ->
      step(platform_context, purge, policy.context, fn ->
        with {:ok, deleted} <- module.purge_tenant_data(scope) do
          {:ok, %{deleted: deleted}}
        end
      end)
    end)
  end

  defp purge_accounts(platform_context, purge) do
    platform_context
    |> step(purge, "identity", fn ->
      with {:ok, user_ids} <-
             Organizations.list_deletable_organization_user_ids(
               platform_context,
               purge.organization_id
             ),
           {:ok, avatar_objects} <- TenantObjectStorage.purge_user_objects(user_ids),
           {:ok, deleted} <- delete_accounts(user_ids) do
        {:ok, %{deleted_accounts: deleted, deleted_avatar_objects: avatar_objects}}
      end
    end)
    |> unwrap_step()
  end

  defp purge_objects(platform_context, purge) do
    retained = RetentionReview.retained_object_prefixes(TenantDataContexts.policies())

    platform_context
    |> step(purge, "storage", fn ->
      TenantObjectStorage.purge_tenant_objects(purge.organization_id, retained)
    end)
    |> unwrap_step()
  end

  defp step(platform_context, purge, name, fun) do
    if Organizations.purge_step_completed?(purge, name) do
      {:cont, {:ok, purge}}
    else
      with {:ok, result} <- fun.(),
           {:ok, purge} <-
             Organizations.record_organization_purge_step(
               platform_context,
               purge.id,
               name,
               result
             ) do
        {:cont, {:ok, purge}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end
  end

  defp unwrap_step({_continue, result}), do: result

  defp delete_accounts(user_ids) do
    Enum.reduce_while(user_ids, {:ok, 0}, fn user_id, {:ok, deleted} ->
      case Identity.find_by_id(user_id) do
        nil ->
          {:cont, {:ok, deleted}}

        user ->
          case Identity.delete_tenant_scoped_user(user) do
            :ok -> {:cont, {:ok, deleted + 1}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end
end
