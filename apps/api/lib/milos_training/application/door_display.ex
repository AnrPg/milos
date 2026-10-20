defmodule MilosTraining.Application.DoorDisplay do
  @moduledoc """
  «Οθόνη πόρτας» on the check-in desk (ADR-155, decision 1): the screen by
  the door shows the location's rotating QR, the next class here with a
  spot, and a welcome line fed live by `check_in:<organization_id>`
  (`checked_in` events, first names only).

  It fetches the current code and the next few (`codes`, each with when it
  shows and until when a scan of it counts), so it keeps rotating through a
  short network drop; a leaked batch is useless about two minutes later.
  `rotate/3` is «Νέος κωδικός πόρτας»: a new seed, and every code shown so
  far stops working.
  """

  alias MilosTraining.Application.{CheckInActions, CheckInFacts, CheckInKeys, PublicURL}
  alias MilosTraining.{Facility, Scheduling}
  alias MilosTraining.Facility.Domain.DoorCode

  @recent_minutes 30
  @next_class_hours 12

  def show(context, location_id, now \\ DateTime.utc_now()) do
    with {:ok, location} <- location(context, location_id),
         {:ok, key} <- CheckInKeys.door_key(context, location.id) do
      rotation = Facility.check_in_rules(context).door_rotation_seconds

      codes =
        key
        |> DoorCode.batch(location.id, now, rotation)
        |> Enum.map(&Map.put(&1, :deep_link, deep_link(location.id, &1.code)))

      [current | _next] = codes

      {:ok,
       %{
         location: %{id: location.id, name: location.name},
         code: current.code,
         deep_link: current.deep_link,
         rotation_seconds: rotation,
         seconds_until_rotation: DoorCode.seconds_until_rotation(now, rotation),
         codes: codes,
         rotated_at: Map.get(location, :door_secret_rotated_at),
         next_class: next_class(context, location.id, now),
         recent_check_ins: recent(context, location.id, now),
         topic: CheckInActions.topic(context.organization_id),
         server_time: now
       }}
    end
  end

  def rotate(context, location_id, now \\ DateTime.utc_now()) do
    with {:ok, location} <- location(context, location_id),
         {:ok, _rotated} <- Facility.rotate_door_secret(context, location.id, now) do
      show(context, location.id, now)
    end
  end

  @doc """
  The printed poster of a location (board 10, Q1 extra): whether it is on,
  its static code and the deep link `/c/<location>/p/<code>` to print. The
  code is shown even while the poster is off, so the owner can print first
  and switch it on after.
  """
  def poster(context, location_id) do
    with {:ok, location} <- location(context, location_id),
         {:ok, key, poster} <- CheckInKeys.poster_key(context, location.id) do
      code = DoorCode.poster_code(key, location.id)

      {:ok,
       %{
         location: %{id: location.id, name: location.name},
         enabled: poster.enabled,
         code: code,
         deep_link: poster_link(location.id, code),
         rotated_at: poster.rotated_at
       }}
    end
  end

  @doc "The owner turns the poster on or off."
  def set_poster(context, location_id, enabled) when is_boolean(enabled) do
    with {:ok, location} <- location(context, location_id),
         {:ok, _location} <- Facility.set_poster_enabled(context, location.id, enabled) do
      poster(context, location.id)
    end
  end

  def set_poster(_context, _location_id, _enabled), do: {:error, :invalid_poster_setting}

  @doc "«Νέος κωδικός αφίσας»: every printed copy stops working."
  def rotate_poster(context, location_id, now \\ DateTime.utc_now()) do
    with {:ok, location} <- location(context, location_id),
         {:ok, _rotated} <- Facility.rotate_poster_secret(context, location.id, now) do
      poster(context, location.id)
    end
  end

  @doc "The path the poster's QR opens: `/c/<location>/p/<code>`."
  def poster_link(location_id, code), do: PublicURL.base_url() <> "/c/#{location_id}/p/#{code}"

  @doc "The path the phone camera opens: `/c/<location>/<code>`."
  def deep_link(location_id, code), do: PublicURL.base_url() <> "/c/#{location_id}/#{code}"

  defp location(context, location_id) do
    case Facility.get_location(context, location_id) do
      %{archived_at: nil} = location -> {:ok, location}
      %{} -> {:error, :location_archived}
      nil -> {:error, :location_not_found}
    end
  end

  defp next_class(context, location_id, now) do
    context
    |> Scheduling.get_calendar_week(%{
      start_at: now,
      end_at: DateTime.add(now, @next_class_hours * 3600, :second),
      class_type_ids: []
    })
    |> Enum.find(fn slot ->
      Map.get(slot, :location_id) in [nil, location_id] and (slot.spots_remaining || 0) > 0
    end)
    |> case do
      nil ->
        nil

      slot ->
        %{
          id: slot.id,
          name: CheckInFacts.class_name(slot),
          starts_at: slot.scheduled_at,
          duration_minutes: slot.duration_minutes,
          spots_remaining: slot.spots_remaining
        }
    end
  end

  # The welcome line: open-gym and class check-ins here in the last half hour,
  # first names only.
  defp recent(context, location_id, now) do
    since = DateTime.add(now, -@recent_minutes * 60, :second)

    open_gym =
      context
      |> Facility.list_check_ins(%{location_id: location_id, since: since, limit: 20})
      |> Enum.map(fn check_in ->
        %{
          first_name: first_word(check_in.display_name),
          kind: "open_gym",
          at: check_in.checked_in_at
        }
      end)

    classes =
      context
      |> Scheduling.list_recent_class_check_ins(since, location_id)
      |> Enum.map(fn check_in ->
        %{first_name: first_word(check_in.display_name), kind: "class", at: check_in.at}
      end)

    (open_gym ++ classes)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(10)
  end

  defp first_word(nil), do: nil

  defp first_word(name),
    do: name |> String.split(~r/[\s_.]+/u, trim: true) |> List.first()
end
