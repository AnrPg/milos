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
  «Ισχύει για» (ADR-186 §8): the params of each item to create, one per
  branch of `location_ids` (each checked like `check/2`), or the params
  themselves when no list is given. Keys keep the params' own style.
  """
  def targets(context, params) when is_map(params) do
    requested = Organizations.requested_location_ids(params)
    single = Map.get(params, :location_id) || Map.get(params, "location_id")

    with {:ok, ids} <- Organizations.location_creation_targets(context, requested, single) do
      if requested == [] do
        {:ok, [Map.drop(params, [:location_ids, "location_ids"])]}
      else
        key = if Map.has_key?(params, "location_ids"), do: "location_id", else: :location_id
        base = Map.drop(params, [:location_ids, "location_ids", :location_id, "location_id"])

        ids
        |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
          item = Map.put(base, key, id)

          case check(context, item) do
            :ok -> {:cont, {:ok, [item | acc]}}
            error -> {:halt, error}
          end
        end)
        |> case do
          {:ok, items} -> {:ok, Enum.reverse(items)}
          error -> error
        end
      end
    end
  end

  @doc """
  Creates one item per params in one transaction: all of them, or none and
  the first error (ADR-186 §8).
  """
  def create_all(context, items, create, transaction \\ &Scheduling.transaction/2)
      when is_function(create, 1) and is_function(transaction, 2) do
    transaction.(context, fn ->
      items
      |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
        case create.(item) do
          {:ok, created} -> {:cont, {:ok, [created | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, created} -> {:ok, Enum.reverse(created)}
        error -> error
      end
    end)
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
