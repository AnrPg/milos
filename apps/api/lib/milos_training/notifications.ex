defmodule MilosTraining.Notifications do
  require Logger

  alias MilosTraining.Identity
  alias MilosTraining.Notifications.Commands.DeletePushSubscription
  alias MilosTraining.Notifications.Commands.DispatchNotification
  alias MilosTraining.Notifications.Commands.EnqueueNotificationEvent
  alias MilosTraining.Notifications.Commands.MarkAllRead
  alias MilosTraining.Notifications.Commands.MarkNotificationRead
  alias MilosTraining.Notifications.Commands.SavePushSubscription
  alias MilosTraining.Notifications.Domain.NotificationDedupe
  alias MilosTraining.Notifications.PushConfig
  alias MilosTraining.Notifications.Queries.GetUnreadCount
  alias MilosTraining.Notifications.Queries.ListInboxPage
  alias MilosTraining.Notifications.Queries.GetPushSubscriptionStatus
  alias MilosTraining.Notifications.Queries.ListPushSubscriptions
  alias MilosTraining.Notifications.NotificationStore
  alias MilosTraining.Notifications.Queries.ListNotifications

  def create_notification(params), do: create_and_broadcast_notification(params)

  def list_for_user(user_id), do: ListNotifications.for_user(user_id)

  def list_inbox(user_id, params \\ %{}) do
    with {:ok, page} <- ListInboxPage.call(user_id, params) do
      {:ok,
       %{
         notifications: page.notifications,
         unread_count: GetUnreadCount.call(user_id),
         next_cursor: page.next_cursor
       }}
    end
  end

  def mark_all_read(user_id) do
    marked_count = MarkAllRead.call(user_id)

    if marked_count > 0 do
      broadcast_notification_changed(user_id)
    end

    marked_count
  end

  def mark_read(user_id, notification_id) do
    case MarkNotificationRead.call(user_id, notification_id) do
      true ->
        broadcast_notification_changed(user_id)
        :ok

      false ->
        {:error, :not_found}
    end
  end

  def push_config do
    %{
      enabled: PushConfig.enabled?(),
      vapid_public_key: PushConfig.public_key()
    }
  end

  def get_push_settings, do: NotificationStore.get_push_settings()

  def update_push_settings(params), do: NotificationStore.update_push_settings(params)

  def save_push_subscription(user_id, attrs) do
    attrs
    |> unwrap_subscription_attrs()
    |> normalize_subscription_attrs(user_id)
    |> SavePushSubscription.call()
  end

  def get_push_subscriptions(user_id), do: ListPushSubscriptions.call(user_id)

  def get_push_subscription_status(user_id, endpoint) when is_binary(endpoint) do
    GetPushSubscriptionStatus.call(user_id, endpoint)
  end

  def delete_push_subscription(user_id, endpoint) when is_binary(endpoint) do
    DeletePushSubscription.call(user_id, endpoint)
  end

  def enqueue_event(event, payload), do: EnqueueNotificationEvent.call(event, payload)

  def dispatch_event(event, payload) when is_atom(event) and is_map(payload) do
    case enqueue_event(event, payload) do
      :ok ->
        :ok

      {:error, reason} ->
        log_notification_event_enqueue_failure(event, reason)

        process_event(Atom.to_string(event), payload)
    end
  end

  def process_event("booking_submitted", booking), do: enqueue_admins_new_booking(booking)

  def process_event("booking_resolved", %{"status" => "approved"} = booking),
    do: enqueue_member_booking_approved(booking)

  def process_event("booking_resolved", %{status: :approved} = booking),
    do: enqueue_member_booking_approved(booking)

  def process_event("booking_resolved", %{"status" => "rejected"} = booking),
    do: enqueue_member_booking_rejected(booking)

  def process_event("booking_resolved", %{status: :rejected} = booking),
    do: enqueue_member_booking_rejected(booking)

  def process_event("booking_timed_out", booking), do: enqueue_booking_timeout_alert(booking)
  def process_event("workout_note_submitted", payload), do: enqueue_workout_note(payload)
  def process_event("admin_note_written", payload), do: enqueue_admin_note(payload)
  def process_event("challenge_completed", payload), do: enqueue_challenge_completed(payload)
  def process_event("workout_rejected", payload), do: enqueue_workout_rejected(payload)
  def process_event("athlete_message_sent", payload), do: enqueue_athlete_message(payload)
  def process_event("workout_moved", payload), do: enqueue_workout_moved(payload)
  def process_event("workout_assigned", payload), do: enqueue_workout_assigned(payload)

  def process_event("workout_assignment_requested", payload),
    do: enqueue_workout_assignment_requested(payload)

  def process_event("review_submitted", payload), do: enqueue_review_submitted(payload)
  def process_event("invoice_issued", payload), do: enqueue_invoice_issued(payload)
  def process_event("payment_reminder", payload), do: enqueue_payment_reminder(payload)
  def process_event(_event, _payload), do: {:error, :bad_request}

  def propagate_nickname_change(old_nickname, new_nickname),
    do: NotificationStore.propagate_nickname_change(old_nickname, new_nickname)

  def enqueue_admins_new_booking(booking),
    do: enqueue_for_users(Identity.list_by_role(:admin), :booking_pending, booking)

  def enqueue_member_booking_approved(booking),
    do: enqueue_for_users([%{id: field(booking, :user_id)}], :booking_approved, booking)

  def enqueue_member_booking_rejected(booking),
    do: enqueue_for_users([%{id: field(booking, :user_id)}], :booking_rejected, booking)

  def enqueue_booking_timeout_alert(booking),
    do: enqueue_for_users(Identity.list_by_role(:admin), :booking_timeout, booking)

  def enqueue_workout_note(note_payload) do
    Identity.list_by_role(:admin)
    |> Enum.each(fn admin ->
      result =
        deliver_notification(
          admin.id,
          :workout_note,
          note_payload
          |> add_default_url()
          |> Map.put_new(:dedupe_key, workout_note_dedupe_key(admin.id, note_payload))
        )

      unless delivered?(result) do
        Logger.error(
          "workout_note delivery failed admin_id=#{admin.id} execution_id=#{field(note_payload, :execution_id)}"
        )
      end
    end)

    :ok
  end

  def enqueue_admin_note(payload) when is_map(payload) do
    athlete_id = field(payload, :athlete_id)

    payload =
      payload
      |> Map.put_new(:url, "/#coach-notes")
      |> Map.put_new(:dedupe_key, admin_note_dedupe_key(athlete_id, payload))

    case deliver_notification(athlete_id, :admin_note, payload) do
      {:ok, _notification} ->
        :ok

      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error(
          "admin_note delivery failed athlete_id=#{athlete_id} reason=#{inspect(reason)}"
        )

        error
    end
  end

  def enqueue_challenge_completed(payload) when is_map(payload) do
    user_id = field(payload, :user_id)

    payload =
      payload
      |> Map.put_new(:url, "/#challenges")
      |> Map.put_new(:dedupe_key, challenge_completed_dedupe_key(user_id, payload))

    case deliver_notification(user_id, :challenge_completed, payload) do
      {:ok, _notification} ->
        :ok

      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error(
          "challenge_completed delivery failed user_id=#{user_id} reason=#{inspect(reason)}"
        )

        error
    end
  end

  def enqueue_workout_changed(user_id, payload) do
    case deliver_notification(user_id, :workout_changed, payload) do
      {:ok, _notification} -> :ok
      {:error, {:push_enqueue_failed, _notification, _reason}} -> :ok
      {:error, _changeset} -> {:error, :notification_failed}
    end
  end

  def enqueue_workout_deleted(user_id, payload) do
    case deliver_notification(user_id, :workout_deleted, payload) do
      {:ok, _notification} -> :ok
      {:error, {:push_enqueue_failed, _notification, _reason}} -> :ok
      {:error, _changeset} -> {:error, :notification_failed}
    end
  end

  def enqueue_workout_rejected(payload) do
    assigned_workout_id = field(payload, :assigned_workout_id)
    workout_title = field(payload, :workout_title)
    athlete_nickname = field(payload, :athlete_nickname)
    scheduled_for = field(payload, :scheduled_for)

    url =
      case scheduled_for do
        nil ->
          "/admin/coaching-assignments?open_assignment=#{assigned_workout_id}"

        date ->
          "/admin/coaching-assignments?open_assignment=#{assigned_workout_id}&date=#{Date.to_iso8601(date)}"
      end

    Identity.list_by_role(:admin)
    |> Enum.each(fn admin ->
      result =
        deliver_notification(admin.id, :workout_rejected, %{
          assigned_workout_id: assigned_workout_id,
          workout_title: workout_title,
          athlete_nickname: athlete_nickname,
          url: url
        })

      unless delivered?(result) do
        Logger.error(
          "workout_rejected delivery failed admin_id=#{admin.id} assigned_workout_id=#{assigned_workout_id}"
        )
      end
    end)

    :ok
  end

  def enqueue_athlete_message(payload) do
    sender_nickname = field(payload, :sender_nickname)
    body = field(payload, :body)
    context_url = field(payload, :context_url) || "/"

    Identity.list_by_role(:admin)
    |> Enum.each(fn admin ->
      result =
        deliver_notification(admin.id, :athlete_message, %{
          sender_id: field(payload, :sender_id),
          sender_nickname: sender_nickname,
          body: body,
          context_url: context_url,
          url: context_url
        })

      unless delivered?(result) do
        Logger.error(
          "athlete_message delivery failed admin_id=#{admin.id} sender_nickname=#{sender_nickname}"
        )
      end
    end)

    :ok
  end

  def enqueue_workout_moved(payload) do
    assigned_workout_id = field(payload, :assigned_workout_id)
    athlete_nickname = field(payload, :athlete_nickname)
    workout_title = field(payload, :workout_title)
    from_date = field(payload, :from_date)
    to_date = field(payload, :to_date)

    url =
      "/admin/coaching-assignments?open_assignment=#{assigned_workout_id}&date=#{to_date}"

    Identity.list_by_role(:admin)
    |> Enum.each(fn admin ->
      result =
        deliver_notification(admin.id, :workout_moved, %{
          assigned_workout_id: assigned_workout_id,
          athlete_nickname: athlete_nickname,
          workout_title: workout_title,
          from_date: from_date,
          to_date: to_date,
          url: url
        })

      unless delivered?(result) do
        Logger.error(
          "workout_moved delivery failed admin_id=#{admin.id} assigned_workout_id=#{assigned_workout_id}"
        )
      end
    end)

    :ok
  end

  def enqueue_workout_assigned(payload) when is_map(payload) do
    assignment_id = field(payload, :assignment_id)
    batch_at = field(payload, :notification_batch_at) || DateTime.utc_now()

    payload
    |> field(:athlete_ids)
    |> List.wrap()
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn athlete_id, :ok ->
      result =
        deliver_notification(athlete_id, :workout_assigned, %{
          assignment_id: assignment_id,
          workout_title: field(payload, :workout_title),
          scheduled_for: field(payload, :scheduled_for),
          dedupe_key: NotificationDedupe.batch_key(athlete_id, :workout_assigned, batch_at),
          url: "/my-workouts"
        })

      if delivered?(result), do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  def enqueue_workout_assignment_requested(payload) when is_map(payload) do
    request_id = field(payload, :request_id)
    athlete_id = field(payload, :athlete_id)
    athlete_nickname = field(payload, :athlete_nickname)
    requested_for = field(payload, :requested_for)
    note = field(payload, :note)
    dedupe_id = request_id || "#{athlete_id}:#{requested_for}"
    url = "/admin/coaching-assignments?date=#{requested_for}"

    Identity.list_by_role(:admin)
    |> Enum.reduce_while(:ok, fn admin, :ok ->
      result =
        deliver_notification(admin.id, :workout_assignment_requested, %{
          athlete_id: athlete_id,
          athlete_nickname: athlete_nickname,
          requested_for: requested_for,
          note: note,
          dedupe_key: "workout-assignment-requested:#{admin.id}:#{dedupe_id}",
          url: url
        })

      if delivered?(result), do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  def enqueue_review_submitted(payload) when is_map(payload) do
    review_id = field(payload, :review_id)

    Identity.list_by_role(:admin)
    |> Enum.reduce_while(:ok, fn admin, :ok ->
      result =
        deliver_notification(admin.id, :review_submitted, %{
          review_id: review_id,
          user_id: field(payload, :user_id),
          target_type: field(payload, :target_type),
          target_id: field(payload, :target_id),
          rating: field(payload, :rating),
          body: field(payload, :body),
          dedupe_key: "review-submitted:#{admin.id}:#{review_id}",
          url: "/admin/reviews"
        })

      if delivered?(result), do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  def enqueue_invoice_issued(invoice) when is_map(invoice) do
    user_id = field(invoice, :user_id)
    invoice_number = field(invoice, :invoice_number)
    total_cents = field(invoice, :total_cents)
    due_date = field(invoice, :due_date)
    invoice_id = field(invoice, :id)

    payload = %{
      invoice_id: invoice_id,
      invoice_number: invoice_number,
      total_cents: total_cents,
      due_date: due_date,
      url: "/account/billing"
    }

    case deliver_notification(user_id, :invoice_issued, payload) do
      {:ok, _notification} ->
        :ok

      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error(
          "invoice_issued delivery failed user_id=#{user_id} invoice_id=#{invoice_id} reason=#{inspect(reason)}"
        )

        error
    end
  end

  def enqueue_payment_reminder(payload) when is_map(payload) do
    user_id = field(payload, :user_id)
    outstanding_cents = field(payload, :outstanding_balance_cents) || 0

    notification_payload = %{
      outstanding_balance_cents: outstanding_cents,
      url: "/account/billing"
    }

    case deliver_notification(user_id, :payment_reminder, notification_payload) do
      {:ok, _notification} ->
        :ok

      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error(
          "payment_reminder delivery failed user_id=#{user_id} reason=#{inspect(reason)}"
        )

        error
    end
  end

  def delete_booking_pending_notifications(booking_id) do
    case NotificationStore.delete_booking_pending_for_booking(booking_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def create_booking_notification_once(user_id, type, booking) do
    case deliver_notification(user_id, type, booking_payload(user_id, type, booking)) do
      {:ok, _notification} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, {:notification_failed, reason}}
    end
  end

  defp enqueue_for_users(users, type, booking) do
    Enum.reduce_while(users, :ok, fn user, :ok ->
      case create_booking_notification_once(user.id, type, booking) do
        :ok ->
          {:cont, :ok}

        {:error, reason} = error ->
          Logger.error(
            "booking notification delivery failed user_id=#{user.id} type=#{type} booking_id=#{field(booking, :id)} reason=#{inspect(reason)}"
          )

          {:halt, error}
      end
    end)
  end

  defp booking_payload(user_id, type, booking) do
    scheduled_class = nested_map(booking, :scheduled_class)
    class_type = scheduled_class && nested_map(scheduled_class, :class_type)

    payload = %{
      booking_id: field(booking, :id),
      scheduled_class_id: field(booking, :scheduled_class_id),
      scheduled_at: scheduled_class && field(scheduled_class, :scheduled_at),
      class_type_id: scheduled_class && field(scheduled_class, :class_type_id),
      class_type_name: class_type && field(class_type, :name),
      user_id: field(booking, :user_id),
      status: to_string(field(booking, :status)),
      admin_message: field(booking, :admin_message),
      dedupe_key: NotificationDedupe.booking_key(user_id, type, field(booking, :id)),
      url: "/schedule"
    }

    if type == :booking_approved do
      batch_at = field(booking, :notification_batch_at) || DateTime.utc_now()

      Map.put(payload, :dedupe_key, NotificationDedupe.batch_key(user_id, type, batch_at))
    else
      payload
    end
  end

  defp deliver_notification(user_id, type, payload) do
    locale =
      case Identity.find_by_id(user_id) do
        %{preferred_locale: preferred_locale} when is_binary(preferred_locale) -> preferred_locale
        _ -> "en"
      end

    case DispatchNotification.call(user_id, type, payload, locale) do
      :ok ->
        :ok

      {:ok, notification} = ok ->
        broadcast_notification_changed(notification.user_id)
        ok

      {:error, {:push_enqueue_failed, notification, _reason}} = error ->
        broadcast_notification_changed(notification.user_id)
        error

      {:error, _reason} = error ->
        error
    end
  end

  defp add_default_url(%{} = payload) do
    execution_id = Map.get(payload, :execution_id) || Map.get(payload, "execution_id")

    case execution_id do
      value when is_binary(value) -> Map.put_new(payload, :url, "/workouts/#{value}/execute")
      _ -> payload
    end
  end

  defp normalize_subscription_attrs(attrs, user_id) do
    keys = Map.get(attrs, :keys) || Map.get(attrs, "keys") || %{}

    %{
      user_id: user_id,
      endpoint: Map.get(attrs, :endpoint) || Map.get(attrs, "endpoint"),
      expiration_time: Map.get(attrs, :expiration_time) || Map.get(attrs, "expiration_time"),
      p256dh_key: Map.get(keys, :p256dh) || Map.get(keys, "p256dh"),
      auth_key: Map.get(keys, :auth) || Map.get(keys, "auth")
    }
  end

  defp unwrap_subscription_attrs(attrs) when is_map(attrs) do
    Map.get(attrs, :push_subscription) ||
      Map.get(attrs, "push_subscription") ||
      Map.get(attrs, :body) ||
      Map.get(attrs, "body") ||
      attrs
  end

  defp broadcast_notification_changed(user_id) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "notifications:changed",
      {:notifications_changed, %{user_id: user_id}}
    )
  end

  defp create_and_broadcast_notification(params) do
    case MilosTraining.Notifications.Commands.CreateNotification.call(params) do
      {:ok, notification} = ok ->
        case notification do
          :duplicate ->
            :ok

          _notification ->
            broadcast_notification_changed(notification.user_id)
            ok
        end

      {:error, _changeset} = error ->
        error
    end
  end

  defp delivered?({:ok, _notification}), do: true
  defp delivered?(:ok), do: true
  defp delivered?(_result), do: false

  defp log_notification_event_enqueue_failure(_event, :oban_unavailable) do
    if Application.get_env(:milos_training, :start_oban, true) do
      Logger.error("notification_event_enqueue_failed reason=:oban_unavailable")
    else
      Logger.debug("notification_event_enqueue_skipped reason=:oban_disabled")
    end
  end

  defp log_notification_event_enqueue_failure(event, reason) do
    Logger.error("notification_event_enqueue_failed event=#{event} reason=#{inspect(reason)}")
  end

  defp field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_map(map, key) do
    case field(map, key) do
      value when is_map(value) -> value
      _ -> nil
    end
  end

  defp workout_note_dedupe_key(user_id, payload) do
    note_id =
      payload
      |> nested_map(:note)
      |> case do
        nil -> nil
        note -> field(note, :id)
      end

    NotificationDedupe.workout_note_key(user_id, note_id)
  end

  defp admin_note_dedupe_key(user_id, payload) do
    NotificationDedupe.admin_note_key(user_id, field(payload, :note_id))
  end

  defp challenge_completed_dedupe_key(user_id, payload) do
    NotificationDedupe.challenge_completed_key(user_id, field(payload, :challenge_id))
  end
end
