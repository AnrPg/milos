defmodule MilosTraining.Infrastructure.Analytics.EctoAnalyticsStore do
  @behaviour MilosTraining.Analytics.Ports.AnalyticsStore

  import Ecto.Query

  alias MilosTraining.Analytics.{
    AnalyticsEvent,
    AttendanceRecord,
    CommunicationMessage,
    CommunicationThread,
    ExerciseCatalogEntry,
    NotificationClickEvent,
    PushDispatchAttempt
  }

  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.Workouts.MasterWorkout
  alias MilosTraining.Repo

  @impl true
  def record_event(params) do
    params =
      params
      |> string_key_map()
      |> Map.put_new("occurred_at", DateTime.utc_now())
      |> normalize_context_id()

    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_event/1)
  end

  @impl true
  def record_notification_click(params) do
    params =
      params
      |> string_key_map()
      |> Map.put_new("clicked_at", DateTime.utc_now())

    %NotificationClickEvent{}
    |> NotificationClickEvent.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_notification_click/1)
  end

  @impl true
  def record_push_attempt(params) do
    params =
      params
      |> string_key_map()
      |> Map.put_new("attempted_at", DateTime.utc_now())

    %PushDispatchAttempt{}
    |> PushDispatchAttempt.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_push_attempt/1)
  end

  @impl true
  def record_attendance(params) do
    params =
      params
      |> string_key_map()
      |> Map.put_new("marked_at", DateTime.utc_now())

    %AttendanceRecord{}
    |> AttendanceRecord.changeset(params)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:booking_id, :status, :marked_by_id, :marked_at, :notes, :params, :updated_at]},
      conflict_target: [:scheduled_class_id, :user_id]
    )
    |> normalize_result(&normalize_attendance/1)
  end

  @impl true
  def get_attendance_for_user_class(user_id, scheduled_class_id) do
    AttendanceRecord
    |> where(
      [record],
      record.user_id == ^user_id and record.scheduled_class_id == ^scheduled_class_id
    )
    |> order_by([record], desc: record.marked_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      %AttendanceRecord{} = record -> normalize_attendance(record)
    end
  end

  @impl true
  def record_communication_message(params) do
    params =
      params
      |> string_key_map()
      |> Map.put_new("channel", "in_app")
      |> Map.put_new("sent_at", DateTime.utc_now())

    Repo.transaction(fn ->
      thread =
        params
        |> get_or_create_communication_thread()
        |> case do
          {:ok, thread} -> thread
          {:error, reason} -> Repo.rollback(reason)
        end

      message_params =
        params
        |> Map.put("thread_id", thread.id)
        |> Map.put_new("params", Map.get(params, "message_params", %{}))

      message =
        %CommunicationMessage{}
        |> CommunicationMessage.changeset(message_params)
        |> Repo.insert()
        |> case do
          {:ok, message} -> message
          {:error, reason} -> Repo.rollback(reason)
        end

      update_thread_last_message(thread, message.sent_at)
      normalize_communication_message(message)
    end)
  end

  @impl true
  def upsert_exercise_catalog_entry(params) do
    changeset = ExerciseCatalogEntry.changeset(%ExerciseCatalogEntry{}, params)
    normalized_name = Ecto.Changeset.get_field(changeset, :normalized_name)

    %ExerciseCatalogEntry{}
    |> ExerciseCatalogEntry.changeset(params)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :name,
           :movement_pattern,
           :equipment,
           :muscle_groups,
           :skill_domain,
           :progression_level,
           :tags,
           :params,
           :active,
           :updated_at
         ]},
      conflict_target: [:normalized_name]
    )
    |> case do
      {:ok, %ExerciseCatalogEntry{id: nil}} ->
        ExerciseCatalogEntry
        |> Repo.get_by(normalized_name: normalized_name)
        |> normalize_entry_result()

      result ->
        normalize_result(result, &normalize_exercise_catalog_entry/1)
    end
  end

  @impl true
  def analytics_summary(params) do
    params = string_key_map(params || %{})
    since = summary_since(params["days"])

    %{
      events: event_summary(since),
      notification_clicks: notification_click_summary(since),
      push_dispatch: push_dispatch_summary(since),
      attendance: attendance_summary(since),
      communication: communication_summary(since),
      exercise_catalog: exercise_catalog_summary(),
      team_workouts: team_workout_summary(since)
    }
  end

  defp event_summary(since) do
    rows =
      AnalyticsEvent
      |> where([event], event.occurred_at >= ^since)
      |> group_by([event], event.event_name)
      |> select([event], {event.event_name, count(event.id)})
      |> Repo.all()

    %{
      since: since,
      total: Enum.reduce(rows, 0, fn {_name, count}, acc -> acc + count end),
      by_name: Map.new(rows)
    }
  end

  defp notification_click_summary(since) do
    total =
      NotificationClickEvent
      |> where([event], event.clicked_at >= ^since)
      |> Repo.aggregate(:count)

    %{since: since, total: total}
  end

  defp push_dispatch_summary(since) do
    rows =
      PushDispatchAttempt
      |> where([attempt], attempt.attempted_at >= ^since)
      |> group_by([attempt], attempt.status)
      |> select([attempt], {attempt.status, count(attempt.id)})
      |> Repo.all()

    %{since: since, by_status: Map.new(rows)}
  end

  defp attendance_summary(since) do
    rows =
      AttendanceRecord
      |> where([record], record.marked_at >= ^since)
      |> group_by([record], record.status)
      |> select([record], {record.status, count(record.id)})
      |> Repo.all()

    %{since: since, by_status: Map.new(rows)}
  end

  defp communication_summary(since) do
    direction_rows =
      CommunicationMessage
      |> where([message], message.sent_at >= ^since)
      |> group_by([message], message.direction)
      |> select([message], {message.direction, count(message.id)})
      |> Repo.all()

    channel_rows =
      CommunicationMessage
      |> where([message], message.sent_at >= ^since)
      |> group_by([message], message.channel)
      |> select([message], {message.channel, count(message.id)})
      |> Repo.all()

    thread_rows =
      CommunicationThread
      |> group_by([thread], thread.status)
      |> select([thread], {thread.status, count(thread.id)})
      |> Repo.all()

    %{
      since: since,
      by_direction: Map.new(direction_rows),
      by_channel: Map.new(channel_rows),
      threads_by_status: Map.new(thread_rows)
    }
  end

  defp exercise_catalog_summary do
    %{
      active_count:
        ExerciseCatalogEntry
        |> where([entry], entry.active == true)
        |> Repo.aggregate(:count),
      total_count: Repo.aggregate(ExerciseCatalogEntry, :count)
    }
  end

  defp team_workout_summary(since) do
    rows =
      WorkoutExecution
      |> join(:inner, [e], w in MasterWorkout, on: e.master_workout_id == w.id)
      |> where([e, _w], not is_nil(e.completed_at_utc) and e.completed_at_utc >= ^since)
      |> group_by([e, w], [e.user_id, w.is_team_workout])
      |> select([e, w], {e.user_id, w.is_team_workout, count(e.id)})
      |> Repo.all()

    aggregate =
      rows
      |> Enum.group_by(fn {_user_id, is_team, _count} -> is_team end)
      |> Map.new(fn {is_team, user_rows} ->
        total = Enum.sum(Enum.map(user_rows, fn {_user_id, _is_team, count} -> count end))
        {is_team, total}
      end)

    by_user =
      rows
      |> Enum.group_by(fn {user_id, _is_team, _count} -> user_id end)
      |> Map.new(fn {user_id, user_rows} ->
        team_count =
          user_rows
          |> Enum.filter(fn {_user_id, is_team, _count} -> is_team end)
          |> Enum.reduce(0, fn {_user_id, _is_team, count}, acc -> acc + count end)

        individual_count =
          user_rows
          |> Enum.filter(fn {_user_id, is_team, _count} -> not is_team end)
          |> Enum.reduce(0, fn {_user_id, _is_team, count}, acc -> acc + count end)

        {user_id,
         %{
           team_count: team_count,
           individual_count: individual_count,
           total_count: team_count + individual_count
         }}
      end)

    %{
      since: since,
      aggregate: %{
        team_count: Map.get(aggregate, true, 0),
        individual_count: Map.get(aggregate, false, 0),
        total_count: Map.get(aggregate, true, 0) + Map.get(aggregate, false, 0)
      },
      by_user: by_user
    }
  end

  defp summary_since(nil), do: DateTime.add(DateTime.utc_now(), -30 * 86_400, :second)

  defp summary_since(days) when is_integer(days) do
    DateTime.add(DateTime.utc_now(), -max(days, 1) * 86_400, :second)
  end

  defp summary_since(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} -> summary_since(value)
      _ -> summary_since(nil)
    end
  end

  defp normalize_context_id(%{"context_id" => nil} = params), do: params

  defp normalize_context_id(%{"context_id" => context_id} = params) when is_binary(context_id),
    do: params

  defp normalize_context_id(params), do: params

  defp normalize_entry_result(nil), do: {:error, :not_found}
  defp normalize_entry_result(entry), do: {:ok, normalize_exercise_catalog_entry(entry)}

  defp normalize_result({:ok, record}, normalizer), do: {:ok, normalizer.(record)}

  defp normalize_result({:error, %Ecto.Changeset{} = changeset}, _normalizer),
    do: {:error, changeset}

  defp normalize_event(%AnalyticsEvent{} = event) do
    %{
      id: event.id,
      event_name: event.event_name,
      user_id: event.user_id,
      actor_role_snapshot: event.actor_role_snapshot,
      context_type: event.context_type,
      context_id: event.context_id,
      occurred_at: event.occurred_at,
      metadata: event.metadata || %{}
    }
  end

  defp normalize_notification_click(%NotificationClickEvent{} = event) do
    %{
      id: event.id,
      notification_id: event.notification_id,
      user_id: event.user_id,
      url: event.url,
      clicked_at: event.clicked_at,
      metadata: event.metadata || %{}
    }
  end

  defp normalize_push_attempt(%PushDispatchAttempt{} = attempt) do
    %{
      id: attempt.id,
      notification_id: attempt.notification_id,
      user_id: attempt.user_id,
      endpoint_hash: attempt.endpoint_hash,
      status: attempt.status,
      attempted_at: attempt.attempted_at,
      completed_at: attempt.completed_at,
      error: attempt.error,
      metadata: attempt.metadata || %{}
    }
  end

  defp normalize_attendance(%AttendanceRecord{} = record) do
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

  defp normalize_communication_message(%CommunicationMessage{} = message) do
    %{
      id: message.id,
      thread_id: message.thread_id,
      sender_id: message.sender_id,
      recipient_id: message.recipient_id,
      sender_role_snapshot: message.sender_role_snapshot,
      recipient_role_snapshot: message.recipient_role_snapshot,
      direction: message.direction,
      channel: message.channel,
      body: message.body,
      sentiment_tag: message.sentiment_tag,
      sent_at: message.sent_at,
      params: message.params || %{},
      inserted_at: message.inserted_at
    }
  end

  defp get_or_create_communication_thread(params) do
    attrs = %{
      context_type: params["context_type"],
      context_id: params["context_id"],
      status: Map.get(params, "thread_status", "open"),
      created_by_id: params["sender_id"],
      assigned_admin_id: params["assigned_admin_id"],
      last_message_at: params["sent_at"],
      params: Map.get(params, "thread_params", %{})
    }

    result =
      %CommunicationThread{}
      |> CommunicationThread.changeset(attrs)
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:context_type, :context_id]
      )

    case result do
      {:ok, %CommunicationThread{id: nil}} ->
        # Conflict: another process won the race; fetch the existing thread.
        case find_communication_thread(params["context_type"], params["context_id"]) do
          %CommunicationThread{} = thread -> {:ok, thread}
          nil -> {:error, :thread_not_found}
        end

      {:ok, thread} ->
        {:ok, thread}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_communication_thread(nil, _context_id), do: nil
  defp find_communication_thread(_context_type, nil), do: nil

  defp find_communication_thread(context_type, context_id) do
    CommunicationThread
    |> where([thread], thread.context_type == ^context_type and thread.context_id == ^context_id)
    |> order_by([thread], desc: thread.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp update_thread_last_message(thread, sent_at) do
    thread
    |> CommunicationThread.changeset(%{last_message_at: sent_at})
    |> Repo.update()
  end

  defp normalize_exercise_catalog_entry(%ExerciseCatalogEntry{} = entry) do
    %{
      id: entry.id,
      name: entry.name,
      normalized_name: entry.normalized_name,
      movement_pattern: entry.movement_pattern,
      equipment: entry.equipment || [],
      muscle_groups: entry.muscle_groups || [],
      skill_domain: entry.skill_domain,
      progression_level: entry.progression_level,
      tags: entry.tags || [],
      params: entry.params || %{},
      active: entry.active,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
