defmodule Palee.Housekeeping do
  @moduledoc """
  The cleaning log (ADR-102): owners and admins define areas and their tasks;
  janitors record when they cleaned what; owners, admins and front desk review
  the log.
  """

  alias Palee.Housekeeping.Domain.CleaningPolicy
  alias Palee.Housekeeping.HousekeepingStore

  def list_areas(context, filters \\ %{}), do: HousekeepingStore.list_areas(context, filters)
  def save_area(context, id, attrs), do: HousekeepingStore.save_area(context, id, attrs)

  def archive_area(context, id),
    do: HousekeepingStore.save_area(context, id, %{archived_at: DateTime.utc_now()})

  def start(context, user_id, area_id, now \\ DateTime.utc_now()) do
    with %{} = area <- HousekeepingStore.get_area(context, area_id) || {:error, :not_found},
         :ok <- CleaningPolicy.can_start?(area) do
      HousekeepingStore.start_entry(context, %{
        area_id: area.id,
        user_id: user_id,
        started_at: now
      })
    end
  end

  def finish(context, user_id, entry_id, params, now \\ DateTime.utc_now()) do
    with %{} = entry <- HousekeepingStore.get_entry(context, entry_id) || {:error, :not_found},
         true <- entry.user_id == user_id || {:error, :forbidden},
         %{} = area <- HousekeepingStore.get_area(context, entry.area_id),
         {:ok, tasks_done} <-
           CleaningPolicy.finish(entry, area, Map.get(params, :tasks_done), now) do
      HousekeepingStore.finish_entry(context, entry.id, %{
        finished_at: now,
        tasks_done: tasks_done,
        note: Map.get(params, :note)
      })
    end
  end

  def list_entries(context, filters \\ %{}), do: HousekeepingStore.list_entries(context, filters)

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: Palee.Housekeeping.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
