defmodule Palee.Application.ClassLocation do
  @moduledoc """
  Checks the optional Facility location of a class, series, appointment slot
  or event (ADR-097), and that branch-scoped staff plan it at one of their
  own branches (ADR-186): they cannot leave the branch empty either, since a
  thing without a branch belongs to the whole business.
  """

  alias Palee.{Facility, Organizations, Scheduling}
  alias Palee.Facility.Domain.CheckInPolicy

  @doc "`:ok` when params name no location or an active one of the organization."
  def check(context, params) when is_map(params) do
    case Map.get(params, :location_id) || Map.get(params, "location_id") do
      id when id in [nil, ""] ->
        Organizations.authorize_location(context, nil)

      id ->
        with :ok <- Organizations.authorize_location(context, id) do
          case Facility.get_location(context, id) do
            nil -> {:error, :location_not_found}
            location -> CheckInPolicy.usable_location(location)
          end
        end
    end
  end

  @doc """
  `:ok` when the acting staff work at the branch of a scheduled class (and
  of its bookings and attendance). Staff who work everywhere skip the read.
  """
  def authorize_class(context, class_id) do
    if Organizations.location_scope(context) == :all do
      :ok
    else
      case Scheduling.get_slot(context, class_id) do
        %{} = slot -> Organizations.authorize_location(context, Map.get(slot, :location_id))
        _missing -> {:error, :not_found}
      end
    end
  end

  @doc "The same for the class a booking is in."
  def authorize_booking(context, booking_id) do
    if Organizations.location_scope(context) == :all do
      :ok
    else
      case Scheduling.get_booking(context, booking_id) do
        %{scheduled_class_id: class_id} -> authorize_class(context, class_id)
        _missing -> {:error, :not_found}
      end
    end
  end

  @doc """
  An appointment slot (ADR-098) is worked by staff of its branch; one without
  a branch (online, at the client's) belongs to its coach and to staff who
  work everywhere.
  """
  def authorize_appointment_slot(context, %{} = slot) do
    cond do
      Organizations.location_scope(context) == :all -> :ok
      is_nil(Map.get(slot, :location_id)) and Map.get(slot, :coach_id) == context.user_id -> :ok
      true -> Organizations.authorize_location(context, Map.get(slot, :location_id))
    end
  end

  @doc "`check/2` for a new appointment slot: a coach's own slot may have no branch."
  def check_appointment(context, params, coach_id) do
    location_id = Map.get(params, :location_id) || Map.get(params, "location_id")

    if location_id in [nil, ""] and coach_id == context.user_id,
      do: :ok,
      else: check(context, params)
  end

  @doc "The current location of a class, for `check_change/3` (nil when none or missing)."
  def class_location(context, class_id) do
    case Scheduling.get_slot(context, class_id) do
      %{} = slot -> Map.get(slot, :location_id)
      _missing -> nil
    end
  end

  @doc """
  An edit of something already at `current_location_id`: the acting staff
  must work there, and a new location in params must pass `check/2`.
  """
  def check_change(context, params, current_location_id) when is_map(params) do
    with :ok <- Organizations.authorize_location(context, current_location_id) do
      if Map.has_key?(params, :location_id) or Map.has_key?(params, "location_id"),
        do: check(context, params),
        else: :ok
    end
  end
end
