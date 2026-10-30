defmodule Palee.Housekeeping do
  @moduledoc """
  The cleaning log (ADR-102): janitors record when they cleaned what; owners,
  admins and front desk review the log. Since ADR-202 the cleaned areas are
  the gym's spaces (`Palee.Spaces`, with their task checklists), and each
  space may have a cleaning schedule: the weekdays and times it should be
  cleaned, with a comment. `Application.CleaningLog` joins the two.
  """

  alias Palee.Housekeeping.Domain.{CleaningPolicy, CleaningSchedule}
  alias Palee.Housekeeping.HousekeepingStore

  @doc "When each of these areas (spaces) was last cleaned: `%{id => finished_at}`."
  def last_cleaned(context, area_ids), do: HousekeepingStore.last_cleaned(context, area_ids)

  @doc "Starts cleaning `area` (a space map with `id`, `archived_at`)."
  def start(context, user_id, area, now \\ DateTime.utc_now()) do
    with :ok <- CleaningPolicy.can_start?(area) do
      HousekeepingStore.start_entry(context, %{
        area_id: area.id,
        user_id: user_id,
        started_at: now
      })
    end
  end

  def get_entry(context, id), do: HousekeepingStore.get_entry(context, id)

  @doc """
  Finishes the caller's own cleaning of `area`, keeping only the area's
  tasks, and the answer for each of its cleaning points (`area.points`,
  ADR-290) when it has any.
  """
  def finish(context, user_id, entry, area, params, now \\ DateTime.utc_now()) do
    with true <- entry.user_id == user_id || {:error, :forbidden},
         {:ok, tasks_done} <-
           CleaningPolicy.finish(entry, area, Map.get(params, :tasks_done), now),
         {:ok, results} <-
           CleaningPolicy.point_results(
             Map.get(area, :points, []),
             Map.get(params, :point_results, [])
           ) do
      HousekeepingStore.finish_entry(context, entry.id, %{
        finished_at: now,
        tasks_done: tasks_done,
        note: Map.get(params, :note),
        point_results: results
      })
    end
  end

  defdelegate not_cleaned(results), to: CleaningPolicy

  def list_entries(context, filters \\ %{}), do: HousekeepingStore.list_entries(context, filters)

  @doc "Every cleaning schedule of the gym (one per space at most)."
  def list_schedules(context), do: HousekeepingStore.list_schedules(context)

  @doc "Sets a space's cleaning schedule (weekdays, times, comment)."
  def put_schedule(context, space_id, attrs) do
    with {:ok, schedule} <- CleaningSchedule.normalize(attrs),
         do: HousekeepingStore.put_schedule(context, space_id, schedule)
  end

  def delete_schedule(context, space_id), do: HousekeepingStore.delete_schedule(context, space_id)

  defdelegate due(spaces, schedules, finished_today, date), to: CleaningSchedule

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: Palee.Housekeeping.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
