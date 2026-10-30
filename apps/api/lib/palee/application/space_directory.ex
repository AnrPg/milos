defmodule Palee.Application.SpaceDirectory do
  @moduledoc """
  Settings › Spaces (ADR-202): the spaces of each branch with their floor
  plans, unavailability, upcoming classes and the machines standing in them.

  Rights (each gym can change the grants in Roles):

    * `manage_spaces` (owner, admin): add, edit, archive, floor plans and
      areas, unavailability;
    * `edit_space_details` (front desk): name, description and directions;
    * `set_space_unavailable` (front desk): unavailability windows;
    * `view_spaces` (coach, front desk): read everything here.

  Branch-scoped staff (ADR-186) see and change only the spaces of their
  branches; a space without a branch belongs to the whole gym.
  """

  alias Palee.Application.{ClassLocation, MediaUrls, SpacePhotos}
  alias Palee.{Inventory, Media, Organizations, Scheduling, Spaces}

  @classes_ahead_days 60
  @detail_fields [:name, :description, :directions]

  @doc "Spaces and floor plans the caller may see; `location_id` narrows to one branch."
  def list(context, filters \\ %{}) do
    spaces =
      context
      |> Spaces.list_spaces(Map.take(filters, [:include_archived, :location_id]))
      |> then(&Organizations.filter_by_location_scope(context, &1))

    windows = Spaces.list_unavailabilities(context, Enum.map(spaces, & &1.id))
    by_space = Enum.group_by(windows, & &1.space_id)

    plans =
      context
      |> Spaces.list_floor_plans(Map.take(filters, [:location_id]))
      |> then(&Organizations.filter_by_location_scope(context, &1))
      |> present_plans(context)

    %{
      spaces: Enum.map(spaces, &Map.put(&1, :unavailability, Map.get(by_space, &1.id, []))),
      floor_plans: plans,
      settings: Spaces.get_settings(context)
    }
  end

  @doc "ADR-290: the gym's choices about its spaces (`floor_plans_in_classes`)."
  def settings(context), do: Spaces.get_settings(context)

  def put_settings(context, params),
    do: Spaces.put_settings(context, Map.take(params, [:floor_plans_in_classes]))

  @doc "One space with its windows, upcoming classes, machines, photos and cleaning points."
  def show(context, id, now \\ DateTime.utc_now()) do
    with {:ok, space} <- fetch(context, id) do
      {:ok,
       space
       |> Map.put(:unavailability, Spaces.list_unavailabilities(context, [space.id], now))
       |> Map.put(:classes, upcoming_classes(context, space.id, now))
       |> Map.put(:equipment, equipment(context, space.id))
       |> Map.merge(SpacePhotos.for_space(context, space.id))}
    end
  end

  @doc "Adds a space (manage_spaces)."
  def create(context, params) do
    with :ok <- ClassLocation.check(context, params),
         :ok <- check_plan(context, params, Map.get(params, :location_id)) do
      Spaces.create_space(context, params)
    end
  end

  @doc "Changes a space; front desk only its details."
  def update(context, id, params) do
    rights = if Organizations.can?(context, :manage_spaces), do: :manage, else: :details

    with :ok <- Spaces.check_fields(params, rights),
         {:ok, space} <- fetch(context, id),
         :ok <- moved_in_scope(context, params),
         location = Map.get(params, :location_id, space.location_id),
         :ok <- check_plan(context, params, location) do
      Spaces.update_space(context, space.id, params)
    end
  end

  @doc "The fields a holder of edit_space_details may change."
  def detail_fields, do: @detail_fields

  def archive(context, id) do
    with {:ok, space} <- fetch(context, id), do: Spaces.archive_space(context, space.id)
  end

  def restore(context, id) do
    with {:ok, space} <- fetch(context, id), do: Spaces.restore_space(context, space.id)
  end

  @doc """
  «Μη διαθέσιμος»: makes the space unavailable from–to with a reason, and
  returns the window and the classes already planned in it (they keep
  their space, flagged on the schedule, so staff can move them).
  """
  def make_unavailable(context, id, params) do
    with {:ok, space} <- fetch(context, id),
         {:ok, window} <- Spaces.make_unavailable(context, space.id, params) do
      {:ok, %{unavailability: window, affected_classes: classes_in(context, space.id, window)}}
    end
  end

  def delete_unavailability(context, id, window_id) do
    with {:ok, space} <- fetch(context, id),
         do: Spaces.delete_unavailability(context, space.id, window_id)
  end

  # ── Floor plans ─────────────────────────────────────────────────────────

  @doc "Adds a floor plan from a ready `floor_plan` upload."
  def create_floor_plan(context, params) do
    media_id = Map.get(params, :media_id)

    with :ok <- ClassLocation.check(context, params),
         {:ok, [_media]} <- Media.fetch_ready(context, "floor_plan", [media_id]),
         {:ok, plan} <- Spaces.create_floor_plan(context, params) do
      _ = Media.set_attached(context, :tenant, [media_id], DateTime.utc_now())
      {:ok, hd(present_plans([plan], context))}
    end
  end

  def update_floor_plan(context, id, params) do
    with {:ok, plan} <- fetch_plan(context, id),
         :ok <- replaced_media(context, Map.get(params, :media_id)),
         {:ok, plan} <- Spaces.update_floor_plan(context, plan.id, params) do
      {:ok, hd(present_plans([plan], context))}
    end
  end

  def delete_floor_plan(context, id) do
    with {:ok, plan} <- fetch_plan(context, id), do: Spaces.delete_floor_plan(context, plan.id)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  @doc "The space if it exists and the caller works at its branch."
  def fetch(context, id) do
    case Spaces.get_space(context, id) do
      nil ->
        {:error, :space_not_found}

      space ->
        with :ok <- Organizations.authorize_location(context, space.location_id), do: {:ok, space}
    end
  end

  defp fetch_plan(context, id) do
    case Spaces.get_floor_plan(context, id) do
      nil ->
        {:error, :floor_plan_not_found}

      plan ->
        with :ok <- Organizations.authorize_location(context, plan.location_id), do: {:ok, plan}
    end
  end

  defp moved_in_scope(context, params) do
    if Map.has_key?(params, :location_id),
      do: ClassLocation.check(context, params),
      else: :ok
  end

  # A space's area is drawn on a floor plan of its own branch.
  defp check_plan(context, params, location_id) do
    case Map.get(params, :floor_plan_id) do
      nil ->
        :ok

      plan_id ->
        case Spaces.get_floor_plan(context, plan_id) do
          nil -> {:error, :floor_plan_not_found}
          %{location_id: ^location_id} -> :ok
          _other -> {:error, :floor_plan_wrong_branch}
        end
    end
  end

  defp replaced_media(_context, nil), do: :ok

  defp replaced_media(context, media_id) do
    with {:ok, _media} <- Media.fetch_ready(context, "floor_plan", [media_id]) do
      _ = Media.set_attached(context, :tenant, [media_id], DateTime.utc_now())
      :ok
    end
  end

  @doc "Floor plans with the URL and size of their image."
  def present_plans([], _context), do: []

  def present_plans(plans, context) do
    media =
      context
      |> Media.list(:tenant, plans |> Enum.map(& &1.media_id) |> Enum.uniq())
      |> Enum.filter(&(&1.status == "ready" and &1.purpose == "floor_plan"))
      |> Map.new(&{&1.id, MediaUrls.present(context, &1)})

    Enum.map(plans, fn plan ->
      shown = Map.get(media, plan.media_id)

      Map.merge(plan, %{
        image_url: shown && shown.url,
        width: shown && shown.width,
        height: shown && shown.height
      })
    end)
  end

  defp upcoming_classes(context, space_id, now) do
    context
    |> Scheduling.get_calendar_week(%{
      start_at: now,
      end_at: DateTime.add(now, @classes_ahead_days * 86_400, :second),
      space_ids: [space_id],
      include_drafts: true
    })
    |> Enum.map(&class_summary/1)
  end

  defp classes_in(context, space_id, window) do
    # A class that started before the window but runs into it is affected too.
    context
    |> Scheduling.get_calendar_week(%{
      start_at: DateTime.add(window.starts_at, -1_440 * 60, :second),
      end_at: window.ends_at,
      space_ids: [space_id],
      include_drafts: true
    })
    |> Enum.filter(&Spaces.blocking_window([window], &1.scheduled_at, &1.duration_minutes))
    |> Enum.map(&class_summary/1)
  end

  defp class_summary(slot) do
    Map.take(slot, [
      :id,
      :name,
      :scheduled_at,
      :duration_minutes,
      :coach_user_id,
      :capacity,
      :approved_booking_count
    ])
  end

  defp equipment(context, space_id) do
    case Inventory.list_placements(context, %{space_id: space_id}) do
      [] ->
        []

      placements ->
        machines = context |> Inventory.list_machines() |> Map.new(&{&1.id, &1})

        placements
        |> Enum.filter(&Map.has_key?(machines, &1.machine_id))
        |> Enum.map(fn placement ->
          machine = machines[placement.machine_id]

          %{
            machine_id: machine.id,
            name: machine.name,
            status: machine.status,
            quantity: placement.quantity
          }
        end)
        |> Enum.sort_by(& &1.name)
    end
  end
end
