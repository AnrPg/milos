defmodule Palee.Infrastructure.Scheduling.EctoDayWorkoutStore do
  @moduledoc "Postgres storage of day WODs (ADR-230)."

  @behaviour Palee.Scheduling.Ports.DayWorkoutStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Scheduling.{Booking, ClassType, DayWorkout, ScheduledClass}

  @active_booking_statuses [:pending, :approved, :waitlisted]

  @impl true
  def transaction(_context, fun) do
    if Repo.in_transaction?() do
      fun.()
    else
      Repo.transaction(fn ->
        case fun.() do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @impl true
  def list_rules(%{organization_id: organization_id}, %Date{} = from, %Date{} = to) do
    DayWorkout
    |> where([rule], rule.organization_id == ^organization_id)
    |> where([rule], rule.local_date >= ^from and rule.local_date <= ^to)
    |> order_by([rule], asc: rule.local_date, asc: rule.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def get_rule(%{organization_id: organization_id}, id) do
    DayWorkout
    |> Repo.get_by(id: id, organization_id: organization_id)
    |> normalize()
  end

  # One rule per day and scope: setting a scope again replaces its WOD.
  @impl true
  def put_rule(%{organization_id: organization_id}, attrs) do
    attrs = Map.put(attrs, :organization_id, organization_id)

    existing =
      DayWorkout
      |> where([rule], rule.organization_id == ^organization_id)
      |> where([rule], rule.local_date == ^attrs.local_date)
      |> scope_where(:class_type_id, attrs[:class_type_id])
      |> scope_where(:location_id, attrs[:location_id])
      |> Repo.one()

    (existing || %DayWorkout{})
    |> DayWorkout.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, rule} -> {:ok, normalize(rule)}
      error -> error
    end
  end

  defp scope_where(query, field, nil), do: where(query, [rule], is_nil(field(rule, ^field)))
  defp scope_where(query, field, value), do: where(query, [rule], field(rule, ^field) == ^value)

  @impl true
  def delete_rule(%{organization_id: organization_id}, id) do
    case Repo.get_by(DayWorkout, id: id, organization_id: organization_id) do
      nil ->
        {:error, :not_found}

      rule ->
        case Repo.delete(rule) do
          {:ok, deleted} -> {:ok, normalize(deleted)}
          error -> error
        end
    end
  end

  @impl true
  def list_classes(%{organization_id: organization_id}, %DateTime{} = from, %DateTime{} = to) do
    booked =
      from(booking in Booking,
        where:
          booking.scheduled_class_id == parent_as(:slot).id and
            booking.status in ^@active_booking_statuses,
        select: 1
      )

    ScheduledClass
    |> from(as: :slot)
    |> join(:left, [slot], type in ClassType, on: type.id == slot.class_type_id)
    |> where([slot], slot.organization_id == ^organization_id)
    |> where([slot], slot.scheduled_at >= ^from and slot.scheduled_at < ^to)
    |> order_by([slot], asc: slot.scheduled_at, asc: slot.name)
    |> select([slot, type], %{
      id: slot.id,
      name: slot.name,
      scheduled_at: slot.scheduled_at,
      class_type_id: slot.class_type_id,
      class_type_name: type.name,
      class_kind: type.kind,
      location_id: slot.location_id,
      class_series_id: slot.class_series_id,
      master_workout_id: slot.master_workout_id,
      day_workout_id: slot.day_workout_id,
      cancelled_at: slot.cancelled_at,
      booked: exists(booked)
    })
    |> Repo.all()
  end

  @impl true
  def apply_changes(%{organization_id: organization_id}, changes) do
    changes
    |> Enum.reduce_while({:ok, []}, fn {class_id, change}, {:ok, acc} ->
      case update_class(organization_id, class_id, change) do
        {1, _} -> {:cont, {:ok, [class_id | acc]}}
        {0, _} -> {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp update_class(organization_id, class_id, change) do
    ScheduledClass
    |> where([slot], slot.organization_id == ^organization_id and slot.id == ^class_id)
    |> Repo.update_all(set: fields(change) ++ [updated_at: NaiveDateTime.utc_now(:second)])
  end

  defp fields({:inherit, rule}),
    do: [master_workout_id: rule.master_workout_id, day_workout_id: rule.id]

  defp fields(:clear), do: [master_workout_id: nil, day_workout_id: nil]
  defp fields(:detach), do: [day_workout_id: nil]

  defp normalize(nil), do: nil

  defp normalize(%DayWorkout{} = rule) do
    %{
      id: rule.id,
      organization_id: rule.organization_id,
      local_date: rule.local_date,
      class_type_id: rule.class_type_id,
      location_id: rule.location_id,
      master_workout_id: rule.master_workout_id,
      set_by_id: rule.set_by_id,
      inserted_at: rule.inserted_at,
      updated_at: rule.updated_at
    }
  end
end
