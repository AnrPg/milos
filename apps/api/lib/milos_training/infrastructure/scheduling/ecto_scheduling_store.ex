defmodule MilosTraining.Infrastructure.Scheduling.EctoSchedulingStore do
  @behaviour MilosTraining.Scheduling.Ports.SchedulingStore

  import Ecto.Query

  alias Ecto.Multi
  alias MilosTraining.Repo
  alias MilosTraining.Scheduling.{Booking, ClassAttendanceRecord, ClassType, ScheduledClass}
  alias MilosTraining.Scheduling.Domain.ClassTypeArchivePolicy
  alias MilosTraining.Workers.BookingTimeoutJob

  @slot_preloads [:bookings, :class_type]

  @impl true
  def create_class_type(params) do
    %ClassType{}
    |> ClassType.create_changeset(params)
    |> Repo.insert()
    |> normalize_class_type_result()
  end

  @impl true
  def update_class_type(id, params) do
    case Repo.get(ClassType, id) do
      nil ->
        {:error, :not_found}

      %ClassType{archived_at: archived_at} when not is_nil(archived_at) ->
        {:error, :class_type_archived}

      class_type ->
        class_type
        |> ClassType.update_changeset(params)
        |> Repo.update()
        |> normalize_class_type_result()
    end
  end

  @impl true
  def archive_class_type(id, replacement_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      source =
        ClassType
        |> where([class_type], class_type.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(source) ->
          Repo.rollback(:not_found)

        not is_nil(source.archived_at) ->
          Repo.rollback(:class_type_archived)

        true ->
          future_query =
            ScheduledClass
            |> where(
              [slot],
              slot.class_type_id == ^id and slot.scheduled_at > ^now
            )

          future_count = Repo.aggregate(future_query, :count)

          active_ids =
            ClassType
            |> where([class_type], is_nil(class_type.archived_at))
            |> select([class_type], class_type.id)
            |> Repo.all()

          case ClassTypeArchivePolicy.validate(future_count, id, replacement_id, active_ids) do
            :ok ->
              if future_count > 0 do
                future_query
                |> lock("FOR UPDATE")
                |> Repo.all()

                Repo.update_all(future_query,
                  set: [class_type_id: replacement_id, updated_at: now]
                )
              end

              source
              |> ClassType.archive_changeset(now)
              |> Repo.update!()
              |> normalize_class_type()
              |> Map.put(:future_classes_reassigned, future_count)

            {:error, :class_type_replacement_required} ->
              Repo.rollback({:class_type_replacement_required, future_count})

            {:error, reason} ->
              Repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, class_type} -> {:ok, class_type}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_class_types(opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)

    ClassType
    |> maybe_include_archived(include_archived)
    |> order_by([class_type], asc: class_type.sort_order, asc: class_type.name)
    |> Repo.all()
    |> Enum.map(&normalize_class_type/1)
  end

  @impl true
  def get_class_type(id, opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)

    ClassType
    |> where([class_type], class_type.id == ^id)
    |> maybe_include_archived(include_archived)
    |> Repo.one()
    |> normalize_class_type()
  end

  @impl true
  def create_slot(params) do
    %ScheduledClass{}
    |> ScheduledClass.changeset(params)
    |> Repo.insert()
    |> wrap_slot_result()
  end

  @impl true
  def update_slot(id, params) do
    case Repo.get(ScheduledClass, id) do
      nil ->
        {:error, :not_found}

      %ScheduledClass{} = slot ->
        slot = Repo.preload(slot, :bookings)

        slot
        |> ScheduledClass.changeset(params)
        |> validate_capacity_not_below_approved(slot)
        |> Repo.update()
        |> wrap_slot_result()
    end
  end

  @impl true
  def delete_slot(id) do
    case Repo.get(ScheduledClass, id) do
      nil ->
        {:error, :not_found}

      %ScheduledClass{} = slot ->
        slot = Repo.preload(slot, :bookings)

        if slot.bookings == [] do
          case Repo.delete(slot) do
            {:ok, _deleted} -> :ok
            {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          end
        else
          changeset =
            Ecto.Changeset.change(slot)
            |> Ecto.Changeset.add_error(:id, "cannot delete a slot with existing bookings")

          {:error, changeset}
        end
    end
  end

  @impl true
  def delete_slots_for_workout(workout_id) do
    slots =
      ScheduledClass
      |> where([slot], slot.master_workout_id == ^workout_id)
      |> Repo.all()
      |> Repo.preload(@slot_preloads)

    Repo.transaction(fn ->
      Enum.reduce_while(slots, [], fn slot, deleted_ids ->
        cancel_booking_timeout_jobs(slot.bookings)

        case Repo.delete(slot) do
          {:ok, _deleted_slot} ->
            {:cont, [slot.id | deleted_ids]}

          {:error, %Ecto.Changeset{} = changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end)
    |> case do
      {:ok, deleted_ids} -> {:ok, Enum.reverse(deleted_ids)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def list_workout_change_targets(workout_id) do
    ScheduledClass
    |> where([slot], slot.master_workout_id == ^workout_id)
    |> Repo.all()
    |> Repo.preload(@slot_preloads)
    |> Enum.flat_map(fn slot ->
      slot.bookings
      |> Enum.filter(&(&1.status in [:pending, :approved]))
      |> Enum.map(fn booking ->
        %{
          user_id: booking.user_id,
          scheduled_class_id: slot.id,
          scheduled_at: slot.scheduled_at,
          class_type_id: slot.class_type_id,
          class_type_name: slot.class_type && slot.class_type.name
        }
      end)
    end)
  end

  @impl true
  def list_slot_ids_for_workout(workout_id) do
    ScheduledClass
    |> where([slot], slot.master_workout_id == ^workout_id)
    |> select([slot], slot.id)
    |> Repo.all()
  end

  @impl true
  def get_slot(id) do
    ScheduledClass
    |> Repo.get(id)
    |> preload_slot()
    |> normalize_slot()
  end

  @impl true
  def list_slots_window(start_at, end_at, opts \\ []) do
    class_type_ids = opts[:class_type_ids] || []

    ScheduledClass
    |> where([slot], slot.scheduled_at >= ^start_at and slot.scheduled_at < ^end_at)
    |> maybe_filter_class_types(class_type_ids)
    |> order_by([slot], asc: slot.scheduled_at)
    |> Repo.all()
    |> Repo.preload(@slot_preloads)
    |> Enum.map(&normalize_slot/1)
  end

  @impl true
  def get_pending_bookings do
    Booking
    |> where([booking], booking.status == :pending)
    |> order_by([booking], asc: booking.inserted_at)
    |> Repo.all()
    |> Repo.preload(:scheduled_class)
    |> Enum.map(&normalize_booking/1)
  end

  @impl true
  def get_booking(id) do
    Booking
    |> Repo.get(id)
    |> preload_booking()
    |> normalize_booking()
  end

  @impl true
  def get_booking_execution_access(booking_id, user_id) do
    Booking
    |> join(:inner, [booking], slot in ScheduledClass, on: slot.id == booking.scheduled_class_id)
    |> where(
      [booking, _slot],
      booking.id == ^booking_id and booking.user_id == ^user_id
    )
    |> select([booking, slot], %{
      booking_id: booking.id,
      status: booking.status,
      master_workout_id: slot.master_workout_id
    })
    |> Repo.one()
    |> case do
      nil -> nil
      access -> %{access | status: to_string(access.status)}
    end
  end

  @impl true
  def record_attendance(params) do
    params =
      params
      |> string_key_map()
      |> Map.put_new("marked_at", DateTime.utc_now())

    %ClassAttendanceRecord{}
    |> ClassAttendanceRecord.changeset(params)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:booking_id, :status, :marked_by_id, :marked_at, :notes, :params, :updated_at]},
      conflict_target: [:scheduled_class_id, :user_id]
    )
    |> case do
      {:ok, %ClassAttendanceRecord{id: nil}} ->
        ClassAttendanceRecord
        |> Repo.get_by(
          scheduled_class_id: params["scheduled_class_id"],
          user_id: params["user_id"]
        )
        |> normalize_attendance_result()

      result ->
        normalize_attendance_result(result)
    end
  end

  @impl true
  def get_attendance_for_user_class(user_id, scheduled_class_id) do
    ClassAttendanceRecord
    |> where(
      [record],
      record.user_id == ^user_id and record.scheduled_class_id == ^scheduled_class_id
    )
    |> order_by([record], desc: record.marked_at)
    |> limit(1)
    |> Repo.one()
    |> normalize_attendance()
  end

  @impl true
  def get_approved_booking_for_class(user_id, scheduled_class_id) do
    Booking
    |> where(
      [booking],
      booking.user_id == ^user_id and
        booking.scheduled_class_id == ^scheduled_class_id and
        booking.status == :approved
    )
    |> order_by([booking], desc: booking.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> preload_booking()
    |> normalize_booking()
  end

  @impl true
  def create_booking(user_id, slot_id, timeout_minutes) do
    Multi.new()
    |> Multi.insert(
      :booking,
      Booking.create_changeset(%Booking{}, %{
        scheduled_class_id: slot_id,
        user_id: user_id,
        status: :pending
      })
    )
    |> Multi.run(:timeout_job, fn repo, %{booking: booking} ->
      booking
      |> timeout_job_changeset(timeout_minutes)
      |> repo.insert()
    end)
    |> Multi.update(:attach_timeout_job, fn %{booking: booking, timeout_job: job} ->
      Booking.timeout_job_changeset(booking, job.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{attach_timeout_job: booking}} ->
        {:ok, booking |> preload_booking() |> normalize_booking()}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  @impl true
  def create_approved_booking(user_id, slot_id) do
    Repo.transaction(fn ->
      slot =
        ScheduledClass
        |> where([scheduled_class], scheduled_class.id == ^slot_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(slot) ->
          Repo.rollback(:not_found)

        approved_booking_count(slot_id) >= slot.capacity ->
          Repo.rollback(:slot_full)

        true ->
          %Booking{}
          |> Booking.create_changeset(%{
            scheduled_class_id: slot_id,
            user_id: user_id,
            status: :approved
          })
          |> Repo.insert()
          |> case do
            {:ok, booking} -> booking
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, booking} -> {:ok, booking |> preload_booking() |> normalize_booking()}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :slot_full} -> {:error, :slot_full}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def approve_booking(id, admin_message) do
    resolve_booking(id, %{status: :approved, admin_message: admin_message})
  end

  @impl true
  def reject_booking(id, admin_message) do
    resolve_booking(id, %{status: :rejected, admin_message: admin_message})
  end

  @impl true
  def reject_booking_with_reconciliation(id, admin_message, reconciliation) do
    resolve_booking(
      id,
      %{status: :rejected, admin_message: admin_message},
      reconciliation
    )
  end

  @impl true
  def attach_timeout_job(booking_id, job_id) do
    case Repo.get(Booking, booking_id) do
      nil ->
        {:error, :not_found}

      %Booking{} = booking ->
        booking
        |> Booking.timeout_job_changeset(job_id)
        |> Repo.update()
        |> wrap_booking_result()
    end
  end

  @impl true
  def withdraw_booking(id) do
    case Repo.get(Booking, id) do
      nil ->
        {:error, :not_found}

      %Booking{status: status} = booking when status in [:pending, :approved] ->
        maybe_cancel_timeout_job(booking.timeout_job_id)
        normalized = booking |> preload_booking() |> normalize_booking()

        case Repo.delete(booking) do
          {:ok, _} -> {:ok, normalized}
          {:error, changeset} -> {:error, changeset}
        end

      %Booking{} ->
        {:error, :booking_not_withdrawable}
    end
  end

  @impl true
  def withdraw_booking_with_reconciliation(id, reconciliation) do
    Repo.transaction(fn ->
      case Repo.get(Booking, id) do
        nil ->
          Repo.rollback(:not_found)

        %Booking{status: status} when status not in [:pending, :approved] ->
          Repo.rollback(:booking_not_withdrawable)

        %Booking{} = booking ->
          normalized = booking |> preload_booking() |> normalize_booking()

          with {:ok, _job} <- insert_reconciliation_job(reconciliation),
               {:ok, _deleted} <- Repo.delete(booking) do
            normalized
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, booking} ->
        maybe_cancel_timeout_job(booking.timeout_job_id)
        {:ok, booking}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def cancel_active_future_bookings_for_user(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      bookings =
        Booking
        |> join(:inner, [booking], slot in ScheduledClass,
          on: slot.id == booking.scheduled_class_id
        )
        |> where(
          [booking, slot],
          booking.user_id == ^user_id and
            booking.status in [:pending, :approved] and
            slot.scheduled_at >= ^now
        )
        |> order_by([booking, _slot], asc: booking.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      Enum.reduce_while(bookings, [], fn booking, booking_ids ->
        maybe_cancel_timeout_job(booking.timeout_job_id)

        case Repo.delete(booking) do
          {:ok, _deleted} -> {:cont, [booking.id | booking_ids]}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
      |> Enum.reverse()
    end)
  end

  defp maybe_cancel_timeout_job(nil), do: :ok

  defp maybe_cancel_timeout_job(job_id) do
    if Application.get_env(:milos_training, :start_oban, true),
      do: Oban.cancel_job(job_id),
      else: :ok
  end

  defp resolve_booking(id, params, reconciliation \\ nil) do
    case Repo.transaction(fn ->
           with {:ok, booking} <- resolve_booking_transaction(id, params),
                {:ok, _job} <- insert_reconciliation_job(reconciliation) do
             {:ok, booking}
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, {:ok, %Booking{} = booking}} ->
        normalized = booking |> preload_booking() |> normalize_booking()
        maybe_cancel_timeout_job(normalized.timeout_job_id)
        {:ok, normalized}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :booking_not_pending} ->
        {:error, :booking_not_pending}

      {:error, :slot_full} ->
        {:error, :slot_full}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp insert_reconciliation_job(nil), do: {:ok, :not_required}

  defp insert_reconciliation_job(args) do
    args
    |> MilosTraining.Workers.ReconcileBookingReleaseJob.new()
    |> Repo.insert()
  end

  defp cancel_booking_timeout_jobs(bookings) do
    Enum.each(bookings, fn booking ->
      case booking.timeout_job_id do
        nil -> :ok
        job_id -> Oban.cancel_job(job_id)
      end
    end)
  end

  defp resolve_booking_transaction(id, params) do
    booking =
      Booking
      |> where([booking], booking.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    cond do
      is_nil(booking) ->
        Repo.rollback(:not_found)

      booking.status != :pending ->
        Repo.rollback(:booking_not_pending)

      approving?(params) and slot_at_capacity?(booking.scheduled_class_id) ->
        Repo.rollback(:slot_full)

      true ->
        case booking |> Booking.resolution_changeset(params) |> Repo.update() do
          {:ok, updated_booking} -> {:ok, updated_booking}
          {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp approving?(%{status: :approved}), do: true
  defp approving?(%{"status" => :approved}), do: true
  defp approving?(_), do: false

  defp slot_at_capacity?(scheduled_class_id) do
    slot =
      ScheduledClass
      |> where([slot], slot.id == ^scheduled_class_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    approved_booking_count(scheduled_class_id) >= slot.capacity
  end

  defp approved_booking_count(scheduled_class_id) do
    Booking
    |> where(
      [booking],
      booking.scheduled_class_id == ^scheduled_class_id and booking.status == :approved
    )
    |> Repo.aggregate(:count)
  end

  defp maybe_filter_class_types(query, []), do: query
  defp maybe_filter_class_types(query, ids), do: where(query, [slot], slot.class_type_id in ^ids)

  defp maybe_include_archived(query, true), do: query

  defp maybe_include_archived(query, false),
    do: where(query, [class_type], is_nil(class_type.archived_at))

  defp preload_slot(nil), do: nil
  defp preload_slot(%ScheduledClass{} = slot), do: Repo.preload(slot, @slot_preloads)

  defp preload_booking(nil), do: nil

  defp preload_booking(%Booking{} = booking),
    do: Repo.preload(booking, scheduled_class: @slot_preloads)

  defp wrap_slot_result({:ok, %ScheduledClass{} = slot}),
    do: {:ok, slot |> preload_slot() |> normalize_slot()}

  defp wrap_slot_result({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset}

  defp wrap_booking_result({:ok, %Booking{} = booking}),
    do: {:ok, booking |> preload_booking() |> normalize_booking()}

  defp wrap_booking_result({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_attendance_result({:ok, record}), do: {:ok, normalize_attendance(record)}

  defp normalize_attendance_result({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, changeset}

  defp normalize_attendance_result(record), do: {:ok, normalize_attendance(record)}

  defp timeout_job_changeset(booking, timeout_minutes) do
    scheduled_at =
      booking.inserted_at
      |> ensure_datetime()
      |> DateTime.add(timeout_minutes * 60, :second)

    BookingTimeoutJob.new(%{"booking_id" => booking.id}, scheduled_at: scheduled_at)
  end

  defp ensure_datetime(%DateTime{} = datetime), do: datetime

  defp ensure_datetime(%NaiveDateTime{} = naive_datetime),
    do: DateTime.from_naive!(naive_datetime, "Etc/UTC")

  defp validate_capacity_not_below_approved(changeset, slot) do
    capacity = Ecto.Changeset.get_field(changeset, :capacity)
    approved_booking_count = Enum.count(slot.bookings, &(&1.status == :approved))

    if is_integer(capacity) and capacity < approved_booking_count do
      Ecto.Changeset.add_error(
        changeset,
        :capacity,
        "cannot be lower than the current approved booking count (#{approved_booking_count})"
      )
    else
      changeset
    end
  end

  defp normalize_slot(nil), do: nil

  defp normalize_slot(%ScheduledClass{} = slot) do
    bookings =
      case slot.bookings do
        %Ecto.Association.NotLoaded{} -> []
        list when is_list(list) -> Enum.map(list, &normalize_booking_summary/1)
        _ -> []
      end

    approved_booking_count = Enum.count(bookings, &(&1.status == :approved))

    %{
      id: slot.id,
      master_workout_id: slot.master_workout_id,
      class_type_id: slot.class_type_id,
      class_type: normalize_loaded_class_type(slot.class_type),
      scheduled_at: slot.scheduled_at,
      capacity: slot.capacity,
      auto_approve: slot.auto_approve,
      booking_timeout_minutes: slot.booking_timeout_minutes,
      approved_booking_count: approved_booking_count,
      spots_remaining: max(slot.capacity - approved_booking_count, 0),
      bookings: bookings,
      inserted_at: slot.inserted_at,
      updated_at: slot.updated_at
    }
  end

  defp normalize_booking(nil), do: nil

  defp normalize_booking(%Booking{} = booking) do
    %{
      id: booking.id,
      scheduled_class_id: booking.scheduled_class_id,
      scheduled_class: normalize_slot(booking.scheduled_class),
      user_id: booking.user_id,
      status: booking.status,
      admin_message: booking.admin_message,
      timeout_job_id: booking.timeout_job_id,
      inserted_at: booking.inserted_at,
      updated_at: booking.updated_at
    }
  end

  defp normalize_booking_summary(%Booking{} = booking) do
    %{
      id: booking.id,
      user_id: booking.user_id,
      status: booking.status,
      admin_message: booking.admin_message,
      timeout_job_id: booking.timeout_job_id,
      inserted_at: booking.inserted_at,
      updated_at: booking.updated_at
    }
  end

  defp normalize_attendance(nil), do: nil

  defp normalize_attendance(%ClassAttendanceRecord{} = record) do
    %{
      id: record.id,
      scheduled_class_id: record.scheduled_class_id,
      booking_id: record.booking_id,
      user_id: record.user_id,
      status: record.status,
      marked_by_id: record.marked_by_id,
      marked_at: record.marked_at,
      notes: record.notes,
      params: record.params || %{},
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp normalize_class_type_result({:ok, class_type}), do: {:ok, normalize_class_type(class_type)}
  defp normalize_class_type_result({:error, changeset}), do: {:error, changeset}

  defp normalize_loaded_class_type(%Ecto.Association.NotLoaded{}), do: nil
  defp normalize_loaded_class_type(class_type), do: normalize_class_type(class_type)

  defp normalize_class_type(nil), do: nil

  defp normalize_class_type(%ClassType{} = class_type) do
    %{
      id: class_type.id,
      name: class_type.name,
      slug: class_type.slug,
      sort_order: class_type.sort_order,
      archived_at: class_type.archived_at,
      inserted_at: class_type.inserted_at,
      updated_at: class_type.updated_at
    }
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  @impl true
  def substitute_slot_workout(slot_id, new_workout_id) do
    case Repo.get(ScheduledClass, slot_id) do
      nil ->
        {:error, :not_found}

      %ScheduledClass{} = slot ->
        case slot |> Ecto.Changeset.change(master_workout_id: new_workout_id) |> Repo.update() do
          {:ok, updated} -> {:ok, %{id: updated.id}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def count_classes_today do
    today = Date.utc_today()
    start_of_day = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    end_of_day = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

    ScheduledClass
    |> where([s], s.scheduled_at >= ^start_of_day and s.scheduled_at <= ^end_of_day)
    |> select([s], count(s.id))
    |> Repo.one()
    |> Kernel.||(0)
  end
end
