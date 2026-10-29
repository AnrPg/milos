defmodule Palee.Application.BoxScreens.BoxScreenAdmin do
  @moduledoc """
  Staff › Box screens (ADR-253), from the phone or the console:

    * list, create (with a pairing code), rename or move to a branch, remove
      (the TV is disconnected at once);
    * a new pairing code (moves the screen to another device);
    * the override: pin what a screen shows (`wod`, `timer`, `leaderboard`,
      `bookings` or one `class`, optionally until a time) and
      «Επιστροφή στο αυτόματο». Who changed it last is kept; the paired TV
      hears it at once.

  Branch-scoped staff (ADR-186) see and manage only their branches' screens;
  a whole-box screen needs staff of every branch.
  """

  alias Palee.{BoxScreens, Facility, Identity, Organizations}
  alias Palee.Application.BoxScreens.{BoxScreenSignals, BoxScreenToday}

  def list(context) do
    now = BoxScreens.now()
    scope = Organizations.location_scope(context)

    screens =
      context
      |> BoxScreens.list()
      |> Enum.filter(&BoxScreens.in_scope?(scope, &1.location_id))

    names = names(Enum.map(screens, & &1.focus_changed_by_id))

    %{
      screens: Enum.map(screens, &view(&1, names, now)),
      max_screens: BoxScreens.max_screens(),
      override_views: BoxScreens.override_views()
    }
  end

  @doc "`{:ok, %{screen, pairing_code: %{code, expires_at}}}`."
  def create(context, params) do
    now = BoxScreens.now()
    location_id = blank(param(params, :location_id))

    with :ok <- branch(context, location_id),
         {:ok, screen, code} <-
           BoxScreens.create(
             context,
             %{name: param(params, :name), location_id: location_id},
             context.user_id,
             now
           ) do
      {:ok, %{screen: view(screen, %{}, now), pairing_code: code}}
    end
  end

  def update(context, id, params) do
    now = BoxScreens.now()

    with {:ok, _screen} <- fetch(context, id),
         {:ok, changes} <- changes(context, params),
         {:ok, screen} <- BoxScreens.update(context, id, changes) do
      BoxScreenSignals.hint(context.organization_id, "screen")
      {:ok, %{screen: view(screen, names([screen.focus_changed_by_id]), now)}}
    end
  end

  def delete(context, id) do
    with {:ok, screen} <- fetch(context, id),
         :ok <- not_found(BoxScreens.delete(context, screen.id)) do
      BoxScreenSignals.disconnect(screen.id)
      :ok
    end
  end

  @doc "`{:ok, %{screen, pairing_code}}`: a new code, replacing any pending one."
  def pairing_code(context, id) do
    now = BoxScreens.now()

    with {:ok, _screen} <- fetch(context, id),
         {:ok, screen, code} <- BoxScreens.new_pairing_code(context, id, now) do
      {:ok, %{screen: view(screen, names([screen.focus_changed_by_id]), now), pairing_code: code}}
    end
  end

  @doc "Pins what the screen shows: `view`, optional `slot_id` (today's class) and `until`."
  def put_override(context, id, params) do
    now = BoxScreens.now()

    with {:ok, screen} <- fetch(context, id),
         slot_ids = BoxScreenToday.slot_ids(context, screen, now),
         {:ok, screen} <-
           BoxScreens.set_override(
             context,
             id,
             %{
               view: param(params, :view),
               slot_id: param(params, :slot_id),
               until: param(params, :until)
             },
             slot_ids,
             context.user_id,
             now
           ) do
      announce(context, screen, now)
      {:ok, %{screen: view(screen, names([screen.focus_changed_by_id]), now)}}
    end
  end

  @doc "«Επιστροφή στο αυτόματο»."
  def delete_override(context, id) do
    now = BoxScreens.now()

    with {:ok, _screen} <- fetch(context, id),
         {:ok, screen} <- BoxScreens.clear_override(context, id, context.user_id, now) do
      announce(context, screen, now)
      {:ok, %{screen: view(screen, names([screen.focus_changed_by_id]), now)}}
    end
  end

  defp announce(context, screen, now) do
    override = BoxScreens.active_override(screen, now)
    BoxScreenSignals.override(context.organization_id, screen.id, override)
    BoxScreenSignals.hint(context.organization_id, "override", override && override.slot_id)
  end

  defp fetch(context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = screen <- BoxScreens.get(context, id),
         true <- BoxScreens.in_scope?(Organizations.location_scope(context), screen.location_id) do
      {:ok, screen}
    else
      _missing -> {:error, :box_screen_not_found}
    end
  end

  defp changes(context, params) do
    changes =
      for key <- [:name, :location_id], has_param?(params, key), into: %{} do
        {key, param(params, key)}
      end

    case Map.fetch(changes, :location_id) do
      {:ok, location_id} ->
        location_id = blank(location_id)
        with :ok <- branch(context, location_id), do: {:ok, %{changes | location_id: location_id}}

      :error ->
        {:ok, changes}
    end
  end

  # The screen's branch: one of the box's active branches the staff member
  # works at, or the whole box (staff of every branch only).
  defp branch(context, location_id) do
    scope = Organizations.location_scope(context)

    cond do
      not BoxScreens.in_scope?(scope, location_id) ->
        {:error, :invalid_screen_branch}

      is_nil(location_id) ->
        :ok

      match?({:ok, _id}, Ecto.UUID.cast(location_id)) and
          match?(%{archived_at: nil}, Facility.get_location(context, location_id)) ->
        :ok

      true ->
        {:error, :invalid_screen_branch}
    end
  end

  defp view(screen, names, now) do
    %{
      id: screen.id,
      name: screen.name,
      location_id: screen.location_id,
      paired: not is_nil(screen.paired_at),
      paired_at: screen.paired_at,
      last_seen_at: screen.last_seen_at,
      pairing_expires_at: pending_code(screen, now),
      override: BoxScreens.active_override(screen, now),
      focus_changed:
        screen.focus_changed_at &&
          %{
            at: screen.focus_changed_at,
            by:
              screen.focus_changed_by_id &&
                %{
                  id: screen.focus_changed_by_id,
                  name: Map.get(names, screen.focus_changed_by_id)
                }
          },
      inserted_at: screen.inserted_at
    }
  end

  defp pending_code(%{pairing_code_expires_at: %DateTime{} = at}, now),
    do: if(DateTime.compare(at, now) == :gt, do: at)

  defp pending_code(_screen, _now), do: nil

  defp names(ids) do
    case ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})
    end
  end

  defp not_found({:error, :not_found}), do: {:error, :box_screen_not_found}
  defp not_found(other), do: other

  defp blank(""), do: nil
  defp blank(value), do: value

  defp has_param?(params, key),
    do: Map.has_key?(params, key) or Map.has_key?(params, Atom.to_string(key))

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
