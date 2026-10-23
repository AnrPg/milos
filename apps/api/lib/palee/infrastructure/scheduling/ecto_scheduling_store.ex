defmodule Palee.Infrastructure.Scheduling.EctoSchedulingStore do
  @behaviour Palee.Scheduling.Ports.SchedulingStore

  import Ecto.Query

  alias Ecto.Multi
  alias Palee.Repo
  alias Palee.Infrastructure.Tenancy.GymClock
  alias Palee.TimeZones.ZonedTime

  alias Palee.Scheduling.{
    Booking,
    ClassAttendanceRecord,
    ClassSeries,
    ClassType,
    ScheduledClass,
    SchedulingSetting
  }

  alias Palee.Scheduling.Domain.{
    BookingOperationPolicy,
    ClassTypeArchivePolicy,
    ClassWorkoutReadiness,
    RecurrenceRule
  }

  alias Palee.Workers.BookingTimeoutJob
  alias Palee.Workers.ClassSeriesExtensionJob
  alias Palee.Workers.ReconcileBookingReleaseJob

  @slot_preloads [:bookings, :class_type, :class_series]

  @impl true
  def create_class_type(%{organization_id: organization_id}, params) do
    params = Map.put(params, :organization_id, organization_id)

    %ClassType{}
    |> ClassType.create_changeset(params)
    |> Repo.insert()
    |> normalize_class_type_result()
  end

  @impl true
  def update_class_type(%{organization_id: organization_id}, id, params) do
    case Repo.get_by(ClassType, id: id, organization_id: organization_id) do
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
  def archive_class_type(%{organization_id: organization_id}, id, replacement_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    tenant_transaction(fn ->
      source =
        ClassType
        |> where([class_type], class_type.id == ^id)
        |> for_organization(organization_id)
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
            |> for_organization(organization_id)

          future_count = Repo.aggregate(future_query, :count)

          active_ids =
            ClassType
            |> where([class_type], is_nil(class_type.archived_at))
            |> for_organization(organization_id)
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
  def list_class_types(%{organization_id: organization_id}, opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)

    ClassType
    |> where([class_type], class_type.organization_id == ^organization_id)
    |> maybe_include_archived(include_archived)
    |> order_by([class_type], asc: class_type.sort_order, asc: class_type.name)
    |> Repo.all()
    |> Enum.map(&normalize_class_type/1)
  end

  @impl true
  def get_class_type(%{organization_id: organization_id}, id, opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)

    ClassType
    |> where(
      [class_type],
      class_type.id == ^id and class_type.organization_id == ^organization_id
    )
    |> maybe_include_archived(include_archived)
    |> Repo.one()
    |> normalize_class_type()
  end

  @impl true
  def create_slot(%{organization_id: organization_id}, params) do
    params = Map.put(params, :organization_id, organization_id)

    %ScheduledClass{}
    |> ScheduledClass.changeset(params)
    |> Repo.insert()
    |> wrap_slot_result()
  end

  @impl true
  def create_class_series(%{organization_id: organization_id}, params) do
    params = params |> string_key_map() |> Map.put("organization_id", organization_id)

    starts_on = parse_series_date(params["starts_on"])
    ends_on = parse_optional_series_date(params["ends_on"])
    horizon = ends_on || Date.add(starts_on || GymClock.today(), 365)
    params = Map.put(params, "materialized_through", horizon)
    changeset = ClassSeries.changeset(%ClassSeries{}, params)

    with {:ok, candidate} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, occurrences} <- RecurrenceRule.occurrences(candidate, horizon: horizon),
         future_occurrences <-
           Enum.filter(occurrences, &(DateTime.compare(&1, DateTime.utc_now()) == :gt)),
         :ok <- require_occurrences(future_occurrences) do
      tenant_transaction(fn ->
        series =
          changeset
          |> Repo.insert()
          |> case do
            {:ok, inserted} -> inserted
            {:error, reason} -> Repo.rollback(reason)
          end

        slots =
          Enum.map(future_occurrences, fn scheduled_at ->
            %ScheduledClass{}
            |> ScheduledClass.changeset(%{
              organization_id: organization_id,
              master_workout_id: series.master_workout_id,
              class_type_id: series.class_type_id,
              location_id: series.location_id,
              coach_user_id: series.coach_user_id,
              class_series_id: series.id,
              name: series.name,
              duration_minutes: series.duration_minutes,
              scheduled_at: scheduled_at,
              capacity: series.capacity,
              auto_approve: series.auto_approve,
              booking_timeout_minutes: series.booking_timeout_minutes
            })
            |> Repo.insert()
            |> case do
              {:ok, slot} -> slot
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        schedule_series_extension(series)

        series
        |> Repo.preload(:class_type)
        |> normalize_class_series()
        |> Map.put(:occurrence_count, length(slots))
      end)
    end
  end

  @impl true
  def extend_class_series(%{organization_id: organization_id}, series_id, %Date{} = horizon) do
    tenant_transaction(fn ->
      series =
        ClassSeries
        |> where([series], series.id == ^series_id)
        |> for_organization(organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(series) ->
          Repo.rollback(:not_found)

        series.status != "active" ->
          Repo.rollback(:class_series_inactive)

        series.ends_on && Date.after?(horizon, series.ends_on) ->
          extend_locked_series(series, series.ends_on)

        true ->
          extend_locked_series(series, horizon)
      end
    end)
  end

  @impl true
  def update_slot(%{organization_id: organization_id}, id, params) do
    case Repo.get_by(ScheduledClass, id: id, organization_id: organization_id) do
      nil ->
        {:error, :not_found}

      %ScheduledClass{} = slot ->
        slot = Repo.preload(slot, :bookings)

        slot
        |> ScheduledClass.changeset(params)
        |> validate_capacity_not_below_approved(slot)
        |> validate_booked_class_keeps_workout(slot)
        |> Repo.update()
        |> wrap_slot_result()
    end
  end

  @impl true
  def delete_slot(%{organization_id: organization_id}, id) do
    case Repo.get_by(ScheduledClass, id: id, organization_id: organization_id) do
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
  def delete_slots_for_workout(%{organization_id: organization_id}, workout_id) do
    slots =
      ScheduledClass
      |> where([slot], slot.master_workout_id == ^workout_id)
      |> for_organization(organization_id)
      |> Repo.all()
      |> Repo.preload(@slot_preloads)

    tenant_transaction(fn ->
      Enum.reduce_while(slots, [], fn slot, deleted_ids ->
        cancel_booking_timeout_jobs(slot.bookings)

        with :ok <- enqueue_booking_release_jobs(slot),
             {:ok, _deleted_slot} <- Repo.delete(slot) do
          {:cont, [slot.id | deleted_ids]}
        else
          {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
    |> case do
      {:ok, deleted_ids} -> {:ok, Enum.reverse(deleted_ids)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp enqueue_booking_release_jobs(slot) do
    slot.bookings
    |> Enum.filter(&(&1.status in [:pending, :approved]))
    |> Enum.reduce_while(:ok, fn booking, :ok ->
      args = %{
        organization_id: slot.organization_id,
        booking_id: booking.id,
        user_id: booking.user_id,
        scheduled_class_id: slot.id,
        reason: "Workout slots deleted",
        idempotency_key: "workout-delete-booking-release:#{booking.id}",
        delete_pending_notification: true
      }

      case Oban.insert(ReconcileBookingReleaseJob.new(args)) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @impl true
  def delete_class_series_for_workout(%{organization_id: organization_id}, workout_id) do
    series =
      ClassSeries
      |> where([series], series.master_workout_id == ^workout_id)
      |> for_organization(organization_id)
      |> Repo.all()

    tenant_transaction(fn ->
      Enum.each(series, &cancel_class_series_extension_jobs/1)

      Enum.each(series, fn series ->
        case Repo.delete(series) do
          {:ok, _deleted_series} -> :ok
          {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        end
      end)

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def list_workout_change_targets(%{organization_id: organization_id}, workout_id) do
    ScheduledClass
    |> where([slot], slot.master_workout_id == ^workout_id)
    |> for_organization(organization_id)
    |> Repo.all()
    |> Repo.preload(@slot_preloads)
    |> Enum.flat_map(fn slot ->
      slot.bookings
      |> Enum.filter(&(&1.status in [:pending, :approved]))
      |> Enum.map(fn booking ->
        %{
          booking_id: booking.id,
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
  def list_slot_ids_for_workout(%{organization_id: organization_id}, workout_id) do
    ScheduledClass
    |> where([slot], slot.master_workout_id == ^workout_id)
    |> for_organization(organization_id)
    |> select([slot], slot.id)
    |> Repo.all()
  end

  @impl true
  def get_slot(%{organization_id: organization_id}, id) do
    ScheduledClass
    |> where([slot], slot.id == ^id)
    |> for_organization(organization_id)
    |> Repo.one()
    |> preload_slot()
    |> normalize_slot()
  end

  @impl true
  def list_slots_window(%{organization_id: organization_id}, start_at, end_at, opts \\ []) do
    class_type_ids = opts[:class_type_ids] || []

    ScheduledClass
    |> where([slot], slot.scheduled_at >= ^start_at and slot.scheduled_at < ^end_at)
    |> for_organization(organization_id)
    |> maybe_filter_class_types(class_type_ids)
    |> maybe_include_drafts(opts[:include_drafts] == true)
    |> order_by([slot], asc: slot.scheduled_at)
    |> Repo.all()
    |> Repo.preload(@slot_preloads)
    |> Enum.map(&normalize_slot/1)
  end

  @impl true
  def list_slots_by_ids(_context, []), do: []

  def list_slots_by_ids(%{organization_id: organization_id}, ids) do
    ScheduledClass
    |> where([slot], slot.id in ^Enum.uniq(ids))
    |> for_organization(organization_id)
    |> Repo.all()
    |> Repo.preload(@slot_preloads)
    |> Enum.map(&normalize_slot/1)
  end

  # The WODs classes in [from, to) use, most recently scheduled first, for the
  # WOD picker's suggestions (the day's WOD, recent ones for a class type).
  @impl true
  def class_workout_usage(%{organization_id: organization_id}, from, to, opts) do
    ScheduledClass
    |> where([slot], not is_nil(slot.master_workout_id))
    |> where([slot], slot.scheduled_at >= ^from and slot.scheduled_at < ^to)
    |> for_organization(organization_id)
    |> maybe_filter_class_types(List.wrap(opts[:class_type_id]))
    |> group_by([slot], slot.master_workout_id)
    |> order_by([slot], desc: max(slot.scheduled_at))
    |> limit(^min(opts[:limit] || 10, 50))
    |> select([slot], %{
      workout_id: slot.master_workout_id,
      last_scheduled_at: max(slot.scheduled_at)
    })
    |> Repo.all()
  end

  # ADR-176: classes still without a WOD that start in [from, to), for the
  # missing-WOD alerts (served by the partial index on master_workout_id).
  @impl true
  def list_slots_missing_workout(%{organization_id: organization_id}, from, to) do
    ScheduledClass
    |> where([slot], is_nil(slot.master_workout_id))
    |> where([slot], slot.scheduled_at >= ^from and slot.scheduled_at < ^to)
    |> for_organization(organization_id)
    |> order_by([slot], asc: slot.scheduled_at)
    |> Repo.all()
    |> Repo.preload([:class_type, :class_series])
    |> Enum.map(&normalize_slot/1)
  end

  @impl true
  def list_member_slots(%{organization_id: organization_id}, user_id, start_at, end_at) do
    Booking
    |> join(:inner, [booking], slot in ScheduledClass, on: slot.id == booking.scheduled_class_id)
    |> where(
      [booking, slot],
      booking.organization_id == ^organization_id and
        slot.organization_id == ^organization_id and booking.user_id == ^user_id and
        booking.status in [:pending, :approved] and
        slot.scheduled_at >= ^start_at and slot.scheduled_at < ^end_at
    )
    |> order_by([_booking, slot], asc: slot.scheduled_at)
    |> preload([booking, slot], scheduled_class: {slot, [:class_type]})
    |> Repo.all()
    |> Enum.map(fn booking ->
      booking.scheduled_class
      |> normalize_slot()
      |> Map.put(:user_booking, normalize_booking(booking))
    end)
  end

  @impl true
  def get_settings(%{organization_id: organization_id}) do
    case Repo.get_by(SchedulingSetting, organization_id: organization_id) do
      nil ->
        %{
          default_capacity: 12,
          default_auto_approve: false,
          default_booking_timeout_minutes: 60,
          default_booking_window_days: nil,
          default_cancellation_cutoff_hours: nil
        }

      settings ->
        normalize_settings(settings)
    end
  end

  @impl true
  def update_settings(%{organization_id: organization_id}, params) do
    settings =
      Repo.get_by(SchedulingSetting, organization_id: organization_id) || %SchedulingSetting{}

    params = Map.put(params, :organization_id, organization_id)

    settings
    |> SchedulingSetting.changeset(params)
    |> Repo.insert_or_update()
    |> case do
      {:ok, updated} -> {:ok, normalize_settings(updated)}
      error -> error
    end
  end

  @impl true
  def get_pending_bookings(%{organization_id: organization_id}) do
    Booking
    |> where([booking], booking.status == :pending)
    |> for_organization(organization_id)
    |> order_by([booking], asc: booking.inserted_at)
    |> Repo.all()
    |> Repo.preload(:scheduled_class)
    |> Enum.map(&normalize_booking/1)
  end

  @impl true
  def get_booking(%{organization_id: organization_id}, id) do
    Booking
    |> where([booking], booking.id == ^id)
    |> for_organization(organization_id)
    |> Repo.one()
    |> preload_booking()
    |> normalize_booking()
  end

  @impl true
  def get_booking_execution_access(
        %{organization_id: organization_id},
        booking_id,
        user_id
      ) do
    Booking
    |> join(:inner, [booking], slot in ScheduledClass, on: slot.id == booking.scheduled_class_id)
    |> where(
      [booking, _slot],
      booking.organization_id == ^organization_id and booking.id == ^booking_id and
        booking.user_id == ^user_id
    )
    |> select([booking, slot], %{
      booking_id: booking.id,
      status: booking.status,
      master_workout_id: slot.master_workout_id,
      # Server-derived tenancy for the execution created from this booking
      # (F-03) - the client must not get to name the organization.
      organization_id: booking.organization_id
    })
    |> Repo.one()
    |> case do
      nil -> nil
      access -> %{access | status: to_string(access.status)}
    end
  end

  @impl true
  def list_class_history(%{organization_id: organization_id}, user_id, opts) do
    limit = Map.get(opts, :limit, 10)
    offset = Map.get(opts, :offset, 0)
    now = DateTime.utc_now()

    base =
      Booking
      |> join(:inner, [booking], slot in ScheduledClass,
        on: slot.id == booking.scheduled_class_id
      )
      |> where(
        [booking, slot],
        booking.organization_id == ^organization_id and booking.user_id == ^user_id and
          booking.status == :approved and slot.scheduled_at <= ^now
      )

    total = Repo.aggregate(base, :count)

    entries =
      base
      |> join(:left, [_booking, slot], class_type in ClassType,
        on: class_type.id == slot.class_type_id
      )
      |> join(:left, [booking, slot], attendance in ClassAttendanceRecord,
        on: attendance.scheduled_class_id == slot.id and attendance.user_id == booking.user_id
      )
      |> order_by([_booking, slot], desc: slot.scheduled_at)
      |> limit(^limit)
      |> offset(^offset)
      |> select([booking, slot, class_type, attendance], %{
        booking_id: booking.id,
        scheduled_class_id: slot.id,
        class_name: slot.name,
        class_type_name: class_type.name,
        scheduled_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes,
        master_workout_id: slot.master_workout_id,
        attendance_status: attendance.status
      })
      |> Repo.all()

    %{entries: entries, total: total}
  end

  @impl true
  def record_attendance(%{organization_id: organization_id}, params) do
    params =
      params
      |> string_key_map()
      |> Map.put("organization_id", organization_id)
      |> Map.put_new("marked_at", DateTime.utc_now())

    %ClassAttendanceRecord{}
    |> ClassAttendanceRecord.changeset(params)
    |> Repo.insert(
      on_conflict: {:replace, attendance_replace_fields(params)},
      conflict_target: [:scheduled_class_id, :user_id]
    )
    |> case do
      {:ok, %ClassAttendanceRecord{id: nil}} ->
        ClassAttendanceRecord
        |> Repo.get_by(
          organization_id: organization_id,
          scheduled_class_id: params["scheduled_class_id"],
          user_id: params["user_id"]
        )
        |> normalize_attendance_result()

      result ->
        normalize_attendance_result(result)
    end
  end

  # ADR-155: a roster mark keeps the method of the check-in it confirms.
  defp attendance_replace_fields(params) do
    base = [:booking_id, :status, :marked_by_id, :marked_at, :notes, :params, :updated_at]
    if params["check_in_method"], do: [:check_in_method | base], else: base
  end

  @impl true
  def delete_attendance(%{organization_id: organization_id}, id) do
    case Repo.get_by(ClassAttendanceRecord, id: id, organization_id: organization_id) do
      nil -> {:error, :not_found}
      record -> record |> Repo.delete() |> normalize_attendance_result()
    end
  end

  @impl true
  def list_recent_class_check_ins(%{organization_id: organization_id}, since, location_id) do
    from(record in ClassAttendanceRecord,
      join: slot in ScheduledClass,
      on: slot.id == record.scheduled_class_id,
      left_join: user in "users",
      on: user.id == record.user_id,
      where:
        record.organization_id == ^organization_id and record.status == "attended" and
          not is_nil(record.check_in_method) and record.marked_at >= ^since,
      order_by: [desc: record.marked_at],
      limit: 20,
      select: %{
        user_id: record.user_id,
        display_name: coalesce(user.display_nickname, user.nickname),
        location_id: slot.location_id,
        method: record.check_in_method,
        at: record.marked_at
      }
    )
    |> then(fn query ->
      if location_id,
        do:
          where(
            query,
            [_record, slot],
            is_nil(slot.location_id) or slot.location_id == ^location_id
          ),
        else: query
    end)
    |> Repo.all()
  end

  @impl true
  def get_attendance(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      ClassAttendanceRecord
      |> Repo.get_by(id: id, organization_id: organization_id)
      |> normalize_attendance()
    else
      :error -> nil
    end
  end

  @impl true
  def list_user_attendance(_context, _user_id, []), do: %{}

  def list_user_attendance(%{organization_id: organization_id}, user_id, slot_ids) do
    ClassAttendanceRecord
    |> where(
      [record],
      record.organization_id == ^organization_id and record.user_id == ^user_id and
        record.scheduled_class_id in ^slot_ids
    )
    |> select([record], {record.scheduled_class_id, record.status})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def get_attendance_for_user_class(
        %{organization_id: organization_id},
        user_id,
        scheduled_class_id
      ) do
    ClassAttendanceRecord
    |> where(
      [record],
      record.organization_id == ^organization_id and record.user_id == ^user_id and
        record.scheduled_class_id == ^scheduled_class_id
    )
    |> order_by([record], desc: record.marked_at)
    |> limit(1)
    |> Repo.one()
    |> normalize_attendance()
  end

  @impl true
  def get_approved_booking_for_class(
        %{organization_id: organization_id},
        user_id,
        scheduled_class_id
      ) do
    Booking
    |> where(
      [booking],
      booking.organization_id == ^organization_id and booking.user_id == ^user_id and
        booking.scheduled_class_id == ^scheduled_class_id and
        booking.status == :approved and is_nil(booking.guest_name)
    )
    |> order_by([booking], desc: booking.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> preload_booking()
    |> normalize_booking()
  end

  @impl true
  def create_booking(context, user_id, slot_id, timeout_minutes),
    do: create_booking_with(context, user_id, slot_id, timeout_minutes, %{})

  # ADR-120 offline replay: keyword options carry the client operation id
  # into the attrs-based write path (ADR-097).
  @impl true
  def create_booking(context, user_id, slot_id, timeout_minutes, opts) when is_list(opts),
    do:
      create_booking_with(context, user_id, slot_id, timeout_minutes, %{
        client_operation_id: Keyword.get(opts, :client_operation_id)
      })

  @impl true
  def get_booking_by_client_operation(
        %{organization_id: organization_id},
        user_id,
        client_operation_id
      ) do
    Booking
    |> where(
      [booking],
      booking.organization_id == ^organization_id and booking.user_id == ^user_id and
        booking.client_operation_id == ^client_operation_id
    )
    |> Repo.one()
    |> preload_booking()
    |> normalize_booking()
  end

  @impl true
  def create_booking_with(
        %{organization_id: organization_id},
        user_id,
        slot_id,
        timeout_minutes,
        attrs
      ) do
    Multi.new()
    |> Multi.run(:slot, fn repo, _changes ->
      case repo.get_by(ScheduledClass, id: slot_id, organization_id: organization_id) do
        nil -> {:error, :not_found}
        slot -> with :ok <- ClassWorkoutReadiness.ensure_published(slot), do: {:ok, slot}
      end
    end)
    |> Multi.insert(
      :booking,
      Booking.create_changeset(
        %Booking{},
        Map.merge(booking_attrs(attrs), %{
          organization_id: organization_id,
          scheduled_class_id: slot_id,
          user_id: user_id,
          status: :pending
        })
      )
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

      {:error, :slot, reason, _changes} when reason in [:not_found, :class_not_published] ->
        {:error, reason}
    end
  end

  @impl true
  def create_approved_booking(context, user_id, slot_id),
    do: create_approved_booking_with(context, user_id, slot_id, %{})

  @impl true
  def create_approved_booking(context, user_id, slot_id, opts) when is_list(opts),
    do:
      create_approved_booking_with(context, user_id, slot_id, %{
        client_operation_id: Keyword.get(opts, :client_operation_id)
      })

  @impl true
  def create_approved_booking_with(%{organization_id: organization_id}, user_id, slot_id, attrs) do
    tenant_transaction(fn ->
      slot =
        ScheduledClass
        |> where(
          [scheduled_class],
          scheduled_class.id == ^slot_id and
            scheduled_class.organization_id == ^organization_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(slot) ->
          Repo.rollback(:not_found)

        not ClassWorkoutReadiness.published?(slot) ->
          Repo.rollback(:class_not_published)

        approved_booking_count(organization_id, slot_id) >= slot.capacity ->
          Repo.rollback(:slot_full)

        true ->
          %Booking{}
          |> Booking.create_changeset(
            Map.merge(booking_attrs(attrs), %{
              organization_id: organization_id,
              scheduled_class_id: slot_id,
              user_id: user_id,
              status: :approved
            })
          )
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
      {:error, :class_not_published} -> {:error, :class_not_published}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def approve_booking(%{organization_id: organization_id}, id, admin_message) do
    resolve_booking(organization_id, id, %{status: :approved, admin_message: admin_message})
  end

  @impl true
  def reject_booking(%{organization_id: organization_id}, id, admin_message) do
    resolve_booking(organization_id, id, %{status: :rejected, admin_message: admin_message})
  end

  @impl true
  def reject_booking_with_reconciliation(
        %{organization_id: organization_id},
        id,
        admin_message,
        reconciliation
      ) do
    resolve_booking(
      organization_id,
      id,
      %{status: :rejected, admin_message: admin_message},
      reconciliation
    )
  end

  @impl true
  def resolve_booking_operation(
        %{organization_id: organization_id},
        id,
        %{status: status} = params,
        reconciliation
      )
      when status in [:approved, :rejected] do
    case tenant_transaction(fn ->
           with {:ok, booking, outcome} <-
                  resolve_booking_operation_transaction(organization_id, id, params),
                {:ok, _job} <- maybe_reconciliation_job(outcome, reconciliation) do
             {booking, outcome}
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, {%Booking{} = booking, outcome}} ->
        normalized = booking |> preload_booking() |> normalize_booking()
        if outcome == :resolved, do: maybe_cancel_timeout_job(normalized.timeout_job_id)
        {:ok, normalized, outcome}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def attach_timeout_job(%{organization_id: organization_id}, booking_id, job_id) do
    case Repo.get_by(Booking, id: booking_id, organization_id: organization_id) do
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
  def timeout_booking(%{organization_id: organization_id}, id) do
    resolve_booking(organization_id, id, %{
      status: :cancelled,
      admin_message: "Booking request timed out"
    })
  end

  @impl true
  def withdraw_booking(%{organization_id: organization_id}, id) do
    case Repo.get_by(Booking, id: id, organization_id: organization_id) do
      nil ->
        {:error, :not_found}

      %Booking{status: status} = booking when status in [:pending, :approved, :waitlisted] ->
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
  def withdraw_booking_with_reconciliation(
        %{organization_id: organization_id},
        id,
        reconciliation
      ) do
    tenant_transaction(fn ->
      case Repo.get_by(Booking, id: id, organization_id: organization_id) do
        nil ->
          Repo.rollback(:not_found)

        %Booking{status: status} when status not in [:pending, :approved, :waitlisted] ->
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

  # ── Waitlist (ADR-097) ──────────────────────────────────────────────────

  @impl true
  def create_waitlisted_booking(%{organization_id: organization_id}, user_id, slot_id, attrs) do
    tenant_transaction(fn ->
      slot =
        ScheduledClass
        |> where([slot], slot.id == ^slot_id and slot.organization_id == ^organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one() || Repo.rollback(:not_found)

      if not ClassWorkoutReadiness.published?(slot), do: Repo.rollback(:class_not_published)

      if approved_booking_count(organization_id, slot.id) < slot.capacity,
        do: Repo.rollback(:slot_not_full)

      %Booking{}
      |> Booking.create_changeset(
        Map.merge(booking_attrs(attrs), %{
          organization_id: organization_id,
          scheduled_class_id: slot.id,
          user_id: user_id,
          status: :waitlisted,
          waitlisted_at: DateTime.utc_now()
        })
      )
      |> Repo.insert()
      |> case do
        {:ok, booking} -> booking
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, booking} -> {:ok, booking |> preload_booking() |> normalize_booking()}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_waitlist(%{organization_id: organization_id}, slot_id) do
    Booking
    |> where([booking], booking.organization_id == ^organization_id)
    |> where([booking], booking.scheduled_class_id == ^slot_id and booking.status == :waitlisted)
    |> Repo.all()
    |> Enum.map(&normalize_booking_summary/1)
  end

  @impl true
  def promote_waitlisted_booking(%{organization_id: organization_id}, booking_id) do
    tenant_transaction(fn ->
      booking =
        Booking
        |> where(
          [booking],
          booking.id == ^booking_id and booking.organization_id == ^organization_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one() || Repo.rollback(:not_found)

      if booking.status != :waitlisted, do: Repo.rollback(:booking_not_waitlisted)

      slot =
        ScheduledClass
        |> where([slot], slot.id == ^booking.scheduled_class_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if approved_booking_count(organization_id, slot.id) >= slot.capacity,
        do: Repo.rollback(:slot_full)

      status = if slot.auto_approve, do: :approved, else: :pending

      promoted =
        booking
        |> Booking.promotion_changeset(status)
        |> Repo.update()
        |> case do
          {:ok, promoted} -> promoted
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if status == :pending do
        {:ok, job} =
          promoted |> timeout_job_changeset(slot.booking_timeout_minutes) |> Repo.insert()

        promoted |> Booking.timeout_job_changeset(job.id) |> Repo.update!()
      else
        promoted
      end
    end)
    |> case do
      {:ok, booking} -> {:ok, booking |> preload_booking() |> normalize_booking()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp booking_attrs(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.take([
      "guest_name",
      "entitlement_allowance",
      "kind",
      "waitlist_priority",
      "client_operation_id"
    ])
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  @impl true
  def cancel_active_future_bookings_for_user(%{organization_id: organization_id}, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    tenant_transaction(fn ->
      bookings =
        Booking
        |> join(:inner, [booking], slot in ScheduledClass,
          on: slot.id == booking.scheduled_class_id
        )
        |> where(
          [booking, slot],
          booking.organization_id == ^organization_id and
            slot.organization_id == ^organization_id and booking.user_id == ^user_id and
            booking.status in [:pending, :approved] and
            slot.scheduled_at >= ^now
        )
        |> order_by([booking, _slot], asc: booking.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      Enum.reduce_while(bookings, [], fn booking, release_facts ->
        maybe_cancel_timeout_job(booking.timeout_job_id)

        case Repo.delete(booking) do
          {:ok, deleted} ->
            {:cont,
             [
               %{
                 booking_id: deleted.id,
                 user_id: deleted.user_id,
                 scheduled_class_id: deleted.scheduled_class_id
               }
               | release_facts
             ]}

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
      |> Enum.reverse()
    end)
  end

  defp maybe_cancel_timeout_job(nil), do: :ok

  defp maybe_cancel_timeout_job(job_id) do
    if Application.get_env(:palee, :start_oban, true),
      do: Oban.cancel_job(job_id),
      else: :ok
  end

  defp resolve_booking(organization_id, id, params, reconciliation \\ nil) do
    case tenant_transaction(fn ->
           with {:ok, booking} <- resolve_booking_transaction(organization_id, id, params),
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
    |> Palee.Workers.ReconcileBookingReleaseJob.new()
    |> Repo.insert()
  end

  defp tenant_transaction(fun) when is_function(fun, 0) do
    if Repo.in_transaction?(), do: {:ok, fun.()}, else: Repo.transaction(fun)
  end

  defp cancel_booking_timeout_jobs(bookings) do
    Enum.each(bookings, fn booking ->
      case booking.timeout_job_id do
        nil -> :ok
        job_id -> Oban.cancel_job(job_id)
      end
    end)
  end

  defp cancel_class_series_extension_jobs(%ClassSeries{id: series_id}) do
    Oban.Job
    |> where([job], job.worker == ^to_string(ClassSeriesExtensionJob))
    |> where([job], fragment("?->>'series_id' = ?", job.args, ^series_id))
    |> Repo.all()
    |> Enum.each(&Oban.cancel_job(&1.id))
  end

  defp resolve_booking_transaction(organization_id, id, params) do
    booking =
      Booking
      |> where(
        [booking],
        booking.id == ^id and booking.organization_id == ^organization_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    cond do
      is_nil(booking) ->
        Repo.rollback(:not_found)

      booking.status != :pending ->
        Repo.rollback(:booking_not_pending)

      approving?(params) and slot_at_capacity?(organization_id, booking.scheduled_class_id) ->
        Repo.rollback(:slot_full)

      true ->
        case booking |> booking_resolution_changeset(params) |> Repo.update() do
          {:ok, updated_booking} -> {:ok, updated_booking}
          {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp resolve_booking_operation_transaction(organization_id, id, params) do
    booking =
      Booking
      |> where(
        [booking],
        booking.id == ^id and booking.organization_id == ^organization_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    with %Booking{} <- booking || {:error, :not_found},
         :proceed <-
           BookingOperationPolicy.resolution_decision(
             booking,
             params.status,
             params.resolution_operation_id
           ),
         :ok <- ensure_capacity_for(params, organization_id, booking) do
      booking
      |> Booking.resolution_changeset(params)
      |> Repo.update()
      |> case do
        {:ok, updated_booking} -> {:ok, updated_booking, :resolved}
        {:error, changeset} -> {:error, changeset}
      end
    else
      :replay -> {:ok, booking, :replayed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_capacity_for(params, organization_id, booking) do
    if approving?(params) and slot_at_capacity?(organization_id, booking.scheduled_class_id),
      do: {:error, :slot_full},
      else: :ok
  end

  defp maybe_reconciliation_job(:resolved, reconciliation),
    do: insert_reconciliation_job(reconciliation)

  defp maybe_reconciliation_job(:replayed, _reconciliation), do: {:ok, :not_required}

  defp booking_resolution_changeset(booking, %{status: :cancelled} = params),
    do: Booking.timeout_changeset(booking, params)

  defp booking_resolution_changeset(booking, params),
    do: Booking.resolution_changeset(booking, params)

  defp approving?(%{status: :approved}), do: true
  defp approving?(_), do: false

  defp slot_at_capacity?(organization_id, scheduled_class_id) do
    slot =
      ScheduledClass
      |> where(
        [slot],
        slot.id == ^scheduled_class_id and slot.organization_id == ^organization_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one!()

    approved_booking_count(organization_id, scheduled_class_id) >= slot.capacity
  end

  defp approved_booking_count(organization_id, scheduled_class_id) do
    Booking
    |> where(
      [booking],
      booking.organization_id == ^organization_id and
        booking.scheduled_class_id == ^scheduled_class_id and booking.status == :approved
    )
    |> Repo.aggregate(:count)
  end

  defp maybe_filter_class_types(query, []), do: query
  defp maybe_filter_class_types(query, ids), do: where(query, [slot], slot.class_type_id in ^ids)

  # ADR-176: drafts (no WOD, no series; see ClassWorkoutReadiness.published?/1)
  # are left out unless a staff view asks for them, so a new member-facing
  # caller can never show one by accident.
  defp maybe_include_drafts(query, true), do: query

  defp maybe_include_drafts(query, false),
    do:
      where(query, [slot], not is_nil(slot.master_workout_id) or not is_nil(slot.class_series_id))

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

    BookingTimeoutJob.new(
      %{
        "organization_id" => booking.organization_id,
        "booking_id" => booking.id
      },
      scheduled_at: scheduled_at
    )
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

  # ADR-176: unlinking the WOD of a standalone class makes it a draft, which
  # members cannot see; a class people already booked keeps a WOD.
  defp validate_booked_class_keeps_workout(changeset, slot) do
    draft? =
      not ClassWorkoutReadiness.published?(%{
        master_workout_id: Ecto.Changeset.get_field(changeset, :master_workout_id),
        class_series_id: Ecto.Changeset.get_field(changeset, :class_series_id)
      })

    if draft? and Enum.any?(slot.bookings, &(&1.status in [:pending, :approved, :waitlisted])),
      do:
        Ecto.Changeset.add_error(changeset, :master_workout_id, "is required once people booked",
          validation: :booked_class_needs_workout
        ),
      else: changeset
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
      organization_id: slot.organization_id,
      master_workout_id: slot.master_workout_id,
      class_series_id: slot.class_series_id,
      class_series: normalize_loaded_class_series(slot.class_series),
      name: slot.name,
      duration_minutes: slot.duration_minutes,
      class_type_id: slot.class_type_id,
      class_type: normalize_loaded_class_type(slot.class_type),
      location_id: slot.location_id,
      coach_user_id: slot.coach_user_id,
      scheduled_at: slot.scheduled_at,
      capacity: slot.capacity,
      auto_approve: slot.auto_approve,
      booking_timeout_minutes: slot.booking_timeout_minutes,
      approved_booking_count: approved_booking_count,
      spots_remaining: max(slot.capacity - approved_booking_count, 0),
      waitlist_count: Enum.count(bookings, &(&1.status == :waitlisted)),
      bookings: bookings,
      inserted_at: slot.inserted_at,
      updated_at: slot.updated_at
    }
  end

  defp normalize_booking(nil), do: nil

  defp normalize_booking(%Booking{} = booking) do
    %{
      id: booking.id,
      organization_id: booking.organization_id,
      scheduled_class_id: booking.scheduled_class_id,
      scheduled_class: normalize_slot(booking.scheduled_class),
      user_id: booking.user_id,
      status: booking.status,
      admin_message: booking.admin_message,
      timeout_job_id: booking.timeout_job_id,
      client_operation_id: booking.client_operation_id,
      resolution_operation_id: booking.resolution_operation_id,
      waitlist_priority: booking.waitlist_priority,
      waitlisted_at: booking.waitlisted_at,
      guest_name: booking.guest_name,
      entitlement_allowance: booking.entitlement_allowance,
      kind: booking.kind,
      inserted_at: booking.inserted_at,
      updated_at: booking.updated_at
    }
  end

  defp normalize_booking_summary(%Booking{} = booking) do
    %{
      id: booking.id,
      organization_id: booking.organization_id,
      user_id: booking.user_id,
      status: booking.status,
      admin_message: booking.admin_message,
      timeout_job_id: booking.timeout_job_id,
      waitlist_priority: booking.waitlist_priority,
      waitlisted_at: booking.waitlisted_at,
      guest_name: booking.guest_name,
      entitlement_allowance: booking.entitlement_allowance,
      kind: booking.kind,
      inserted_at: booking.inserted_at,
      updated_at: booking.updated_at
    }
  end

  defp normalize_attendance(nil), do: nil

  defp normalize_attendance(%ClassAttendanceRecord{} = record) do
    %{
      id: record.id,
      organization_id: record.organization_id,
      scheduled_class_id: record.scheduled_class_id,
      booking_id: record.booking_id,
      user_id: record.user_id,
      status: record.status,
      marked_by_id: record.marked_by_id,
      marked_at: record.marked_at,
      notes: record.notes,
      params: record.params || %{},
      check_in_method: record.check_in_method,
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
      organization_id: class_type.organization_id,
      name: class_type.name,
      slug: class_type.slug,
      sort_order: class_type.sort_order,
      archived_at: class_type.archived_at,
      credit_cost: class_type.credit_cost,
      kind: class_type.kind,
      level: class_type.level,
      audiences: class_type.audiences,
      inserted_at: class_type.inserted_at,
      updated_at: class_type.updated_at
    }
  end

  defp normalize_loaded_class_series(%Ecto.Association.NotLoaded{}), do: nil
  defp normalize_loaded_class_series(nil), do: nil
  defp normalize_loaded_class_series(series), do: normalize_class_series(series)

  defp normalize_class_series(%ClassSeries{} = series) do
    %{
      id: series.id,
      organization_id: series.organization_id,
      master_workout_id: series.master_workout_id,
      class_type_id: series.class_type_id,
      location_id: series.location_id,
      coach_user_id: series.coach_user_id,
      name: series.name,
      duration_minutes: series.duration_minutes,
      timezone: series.timezone,
      starts_on: series.starts_on,
      ends_on: series.ends_on,
      local_start_time: series.local_start_time,
      weekdays: series.weekdays,
      excluded_dates: series.excluded_dates,
      materialized_through: series.materialized_through,
      capacity: series.capacity,
      auto_approve: series.auto_approve,
      booking_timeout_minutes: series.booking_timeout_minutes,
      status: series.status
    }
  end

  defp parse_series_date(%Date{} = date), do: date

  defp parse_series_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_series_date(_), do: nil
  defp parse_optional_series_date(nil), do: nil
  defp parse_optional_series_date(""), do: nil
  defp parse_optional_series_date(value), do: parse_series_date(value)

  defp require_occurrences([]), do: {:error, :no_future_occurrences}
  defp require_occurrences(_occurrences), do: :ok

  defp extend_locked_series(series, horizon) do
    starts_on = Date.add(series.materialized_through, 1)

    if Date.after?(starts_on, horizon) do
      normalize_class_series(series)
    else
      rule = %{series | starts_on: starts_on}

      with {:ok, occurrences} <- RecurrenceRule.occurrences(rule, horizon: horizon) do
        Enum.each(occurrences, fn scheduled_at ->
          %ScheduledClass{}
          |> ScheduledClass.changeset(%{
            organization_id: series.organization_id,
            master_workout_id: series.master_workout_id,
            class_type_id: series.class_type_id,
            location_id: series.location_id,
            coach_user_id: series.coach_user_id,
            class_series_id: series.id,
            name: series.name,
            duration_minutes: series.duration_minutes,
            scheduled_at: scheduled_at,
            capacity: series.capacity,
            auto_approve: series.auto_approve,
            booking_timeout_minutes: series.booking_timeout_minutes
          })
          |> Repo.insert!()
        end)

        updated =
          series
          |> Ecto.Changeset.change(materialized_through: horizon)
          |> Repo.update!()

        schedule_series_extension(updated)

        updated
        |> normalize_class_series()
        |> Map.put(:occurrence_count, length(occurrences))
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp schedule_series_extension(%ClassSeries{ends_on: ends_on}) when not is_nil(ends_on), do: :ok

  defp schedule_series_extension(%ClassSeries{} = series) do
    next_horizon = Date.add(series.materialized_through, 365)
    run_on = Date.add(series.materialized_through, -30)
    scheduled_at = DateTime.new!(run_on, ~T[02:00:00], "Etc/UTC")

    %{
      "organization_id" => series.organization_id,
      "series_id" => series.id,
      "horizon" => Date.to_iso8601(next_horizon)
    }
    |> ClassSeriesExtensionJob.new(scheduled_at: scheduled_at)
    |> Repo.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  @impl true
  def substitute_slot_workout(%{organization_id: organization_id}, slot_id, new_workout_id) do
    case Repo.get_by(ScheduledClass, id: slot_id, organization_id: organization_id) do
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
  def count_classes_today(%{organization_id: organization_id}) do
    zone = GymClock.zone(organization_id)
    today = ZonedTime.local_date(DateTime.utc_now(), zone)
    start_of_day = ZonedTime.start_of_day(today, zone)
    next_day = ZonedTime.start_of_day(Date.add(today, 1), zone)

    ScheduledClass
    |> where([s], s.scheduled_at >= ^start_of_day and s.scheduled_at < ^next_day)
    |> for_organization(organization_id)
    |> select([s], count(s.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp normalize_settings(settings) do
    %{
      id: settings.id,
      organization_id: settings.organization_id,
      default_capacity: settings.default_capacity,
      default_auto_approve: settings.default_auto_approve,
      default_booking_timeout_minutes: settings.default_booking_timeout_minutes,
      default_booking_window_days: settings.default_booking_window_days,
      default_cancellation_cutoff_hours: settings.default_cancellation_cutoff_hours,
      inserted_at: settings.inserted_at,
      updated_at: settings.updated_at
    }
  end

  @impl true
  def list_active_class_series(%{organization_id: organization_id}) do
    today = GymClock.today_for(organization_id)

    ClassSeries
    |> for_organization(organization_id)
    |> where([series], series.status == "active")
    |> where([series], is_nil(series.ends_on) or series.ends_on >= ^today)
    |> order_by([series], asc: series.local_start_time, asc: series.name)
    |> Repo.all()
    |> Enum.map(&normalize_class_series/1)
  end

  # Approved bookings per member and series since `since` (ADR-138 D7).
  @impl true
  def series_booking_counts(%{organization_id: organization_id}, since) do
    Booking
    |> for_organization(organization_id)
    |> join(:inner, [booking], slot in ScheduledClass, on: slot.id == booking.scheduled_class_id)
    |> where(
      [booking, slot],
      booking.status == :approved and not is_nil(slot.class_series_id) and
        slot.scheduled_at >= ^since and not is_nil(booking.user_id)
    )
    |> group_by([booking, slot], [slot.class_series_id, booking.user_id])
    |> select([booking, slot], %{
      series_id: slot.class_series_id,
      user_id: booking.user_id,
      count: count(booking.id)
    })
    |> Repo.all()
  end

  defp for_organization(query, organization_id) do
    where(query, [row], row.organization_id == ^organization_id)
  end
end
