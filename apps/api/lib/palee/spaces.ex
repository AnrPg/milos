defmodule Palee.Spaces do
  @moduledoc """
  The spaces of a gym (ADR-202): rooms and areas of each branch, the floor
  plans they are drawn on, and the times they are unavailable. Classes take
  place in a space; the cleaning log (ADR-102) cleans them.
  """

  alias Palee.Spaces.Domain.{SpacePolicy, TenantDataPolicy}
  alias Palee.Spaces.SpaceStore

  @doc "Spaces of the gym; filters: `include_archived`, `location_id` (nil for none), `ids`."
  def list_spaces(context, filters \\ %{}), do: SpaceStore.list_spaces(context, filters)
  def get_space(context, id), do: SpaceStore.get_space(context, id)

  def create_space(context, attrs), do: SpaceStore.save_space(context, nil, attrs)
  def update_space(context, id, attrs), do: SpaceStore.save_space(context, id, attrs)

  def archive_space(context, id, now \\ DateTime.utc_now()),
    do: SpaceStore.save_space(context, id, %{archived_at: now})

  def restore_space(context, id), do: SpaceStore.save_space(context, id, %{archived_at: nil})

  def list_floor_plans(context, filters \\ %{}), do: SpaceStore.list_floor_plans(context, filters)
  def get_floor_plan(context, id), do: SpaceStore.get_floor_plan(context, id)
  def create_floor_plan(context, attrs), do: SpaceStore.save_floor_plan(context, nil, attrs)
  def update_floor_plan(context, id, attrs), do: SpaceStore.save_floor_plan(context, id, attrs)
  def delete_floor_plan(context, id), do: SpaceStore.delete_floor_plan(context, id)

  @doc "Unavailability windows of these spaces that end after `from` (default now)."
  def list_unavailabilities(context, space_ids, from \\ DateTime.utc_now())
  def list_unavailabilities(_context, [], _from), do: []

  def list_unavailabilities(context, space_ids, from),
    do: SpaceStore.list_unavailabilities(context, Enum.uniq(space_ids), from)

  @doc "Makes a space unavailable from `starts_at` to `ends_at`, with an optional reason."
  def make_unavailable(context, space_id, attrs) do
    starts_at = Map.get(attrs, :starts_at)
    ends_at = Map.get(attrs, :ends_at)

    with :ok <- SpacePolicy.validate_window(starts_at, ends_at) do
      SpaceStore.create_unavailability(context, %{
        space_id: space_id,
        starts_at: starts_at,
        ends_at: ends_at,
        reason: Map.get(attrs, :reason),
        created_by_id: Map.get(context, :user_id)
      })
    end
  end

  def delete_unavailability(context, space_id, id),
    do: SpaceStore.delete_unavailability(context, space_id, id)

  @doc """
  `:ok` when a class at `starts_at` lasting `duration_minutes` can take place
  in the space, or `{:error, {:space_unavailable, window}}`.
  """
  def check_available(context, space_id, %DateTime{} = starts_at, duration_minutes) do
    context
    |> list_unavailabilities([space_id], starts_at)
    |> SpacePolicy.check_available(starts_at, duration_minutes)
  end

  defdelegate check_fields(params, rights), to: SpacePolicy
  defdelegate overlapping_ids(classes), to: SpacePolicy
  defdelegate blocking_window(windows, starts_at, duration_minutes), to: SpacePolicy
  defdelegate usable(space), to: SpacePolicy
  defdelegate same_branch(space, location_id), to: SpacePolicy

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
