defmodule MilosTraining.Notifications do
  require Logger

  alias MilosTraining.{Identity, Organizations}
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
  alias MilosTraining.Notifications.PushSubscriptionStore
  alias MilosTraining.Notifications.Queries.ListNotifications

  def create_notification(params), do: create_and_broadcast_notification(params)

  def list_for_user(user_id),
    do:
      NotificationStore.with_user_context(%{user_id: user_id}, fn ->
        ListNotifications.for_user(user_id)
      end)

  def list_inbox(user_id, params \\ %{}) do
    NotificationStore.with_user_context(%{user_id: user_id}, fn ->
      with {:ok, page} <- ListInboxPage.call(user_id, params) do
        {:ok,
         %{
           notifications: page.notifications,
           unread_count: GetUnreadCount.call(user_id),
           next_cursor: page.next_cursor
         }}
      end
    end)
  end

  def mark_all_read(user_id) do
    marked_count =
      NotificationStore.with_user_context(%{user_id: user_id}, fn -> MarkAllRead.call(user_id) end)

    if marked_count > 0 do
      broadcast_notification_changed(user_id)
    end

    marked_count
  end

  def mark_read(user_id, notification_id) do
    case NotificationStore.with_user_context(%{user_id: user_id}, fn ->
           MarkNotificationRead.call(user_id, notification_id)
         end) do
      true ->
        broadcast_notification_changed(user_id)
        :ok

      false ->
        {:error, :not_found}
    end
  end

  def get_notification_organization_id(user_id, notification_id),
    do: NotificationStore.get_notification_organization_id(user_id, notification_id)

  def push_config do
    %{
      enabled: PushConfig.enabled?(),
      vapid_public_key: PushConfig.public_key()
    }
  end

  def get_push_settings, do: NotificationStore.get_push_settings()

  def update_push_settings(params), do: NotificationStore.update_push_settings(params)

  def save_push_subscription(user_id, attrs) do
    PushSubscriptionStore.with_user_context(%{user_id: user_id}, fn ->
      attrs
      |> unwrap_subscription_attrs()
      |> normalize_subscription_attrs(user_id)
      |> SavePushSubscription.call()
    end)
  end

  def get_push_subscriptions(user_id),
    do:
      PushSubscriptionStore.with_user_context(%{user_id: user_id}, fn ->
        ListPushSubscriptions.call(user_id)
      end)

  def get_push_subscription_status(user_id, endpoint) when is_binary(endpoint) do
    PushSubscriptionStore.with_user_context(%{user_id: user_id}, fn ->
      GetPushSubscriptionStatus.call(user_id, endpoint)
    end)
  end

  def delete_push_subscription(user_id, endpoint) when is_binary(endpoint) do
    PushSubscriptionStore.with_user_context(%{user_id: user_id}, fn ->
      DeletePushSubscription.call(user_id, endpoint)
    end)
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
  def process_event("chat_message", payload), do: enqueue_chat_message(payload)
  def process_event("workout_moved", payload), do: enqueue_workout_moved(payload)
  def process_event("workout_assigned", payload), do: enqueue_workout_assigned(payload)

  def process_event("workout_assignment_requested", payload),
    do: enqueue_workout_assignment_requested(payload)

  def process_event("review_submitted", payload), do: enqueue_review_submitted(payload)
  def process_event("invoice_issued", payload), do: enqueue_invoice_issued(payload)
  def process_event("payment_reminder", payload), do: enqueue_payment_reminder(payload)

  def process_event("booking_waitlist_promoted", payload),
    do:
      enqueue_simple(:booking_waitlist_promoted, payload, %{
        class_name: field(payload, :class_name),
        scheduled_at: field(payload, :scheduled_at),
        booking_id: field(payload, :booking_id),
        scheduled_class_id: field(payload, :scheduled_class_id),
        status: field(payload, :status),
        url: "/schedule"
      })

  def process_event("package_expiring", payload),
    do:
      enqueue_simple(:package_expiring, payload, %{
        package_name: field(payload, :package_name),
        ends_on: field(payload, :ends_on),
        days: field(payload, :days),
        subscription_id: field(payload, :subscription_id),
        url: "/account/billing"
      })

  # ADR-098 coaching notifications.
  def process_event("form_review_submitted", payload),
    do:
      enqueue_simple(:form_review_submitted, payload, %{
        form_review_id: field(payload, :form_review_id),
        client_nickname: field(payload, :client_nickname),
        exercise_name: field(payload, :exercise_name),
        url: "/admin/coaching?tab=form-reviews"
      })

  def process_event("form_review_completed", payload),
    do:
      enqueue_simple(:form_review_completed, payload, %{
        form_review_id: field(payload, :form_review_id),
        exercise_name: field(payload, :exercise_name),
        url: "/coaching"
      })

  def process_event("coaching_reply_overdue", payload),
    do:
      enqueue_simple(:coaching_reply_overdue, payload, %{
        thread_id: field(payload, :thread_id),
        client_nickname: field(payload, :client_nickname),
        due_at: field(payload, :due_at),
        url: "/admin/coaching?tab=replies"
      })

  def process_event("nutrition_plan_updated", payload),
    do:
      enqueue_simple(:nutrition_plan_updated, payload, %{
        title: field(payload, :title),
        url: "/coaching"
      })

  def process_event("appointment_booked", payload),
    do:
      enqueue_simple(:appointment_booked, payload, %{
        slot_id: field(payload, :slot_id),
        kind: field(payload, :kind),
        starts_at: field(payload, :starts_at),
        client_nickname: field(payload, :client_nickname),
        url: "/admin/appointments"
      })

  def process_event("appointment_cancelled", payload),
    do:
      enqueue_simple(:appointment_cancelled, payload, %{
        slot_id: field(payload, :slot_id),
        kind: field(payload, :kind),
        starts_at: field(payload, :starts_at),
        url: field(payload, :url) || "/appointments"
      })

  # ADR-100: owners and admins see when a coach takes an athlete.
  def process_event("coach_client_assigned", payload),
    do:
      enqueue_simple(:coach_client_assigned, payload, %{
        coach_nickname: field(payload, :coach_nickname),
        client_nickname: field(payload, :client_nickname),
        client_user_id: field(payload, :client_user_id),
        url: "/admin/users/#{field(payload, :client_user_id)}"
      })

  # ADR-101: a coach learns which admin read which note, and when.
  def process_event("coach_note_viewed", payload),
    do:
      enqueue_simple(:coach_note_viewed, payload, %{
        note_id: field(payload, :note_id),
        reader_nickname: field(payload, :reader_nickname),
        client_nickname: field(payload, :client_nickname),
        read_at: field(payload, :read_at),
        url: "/admin/users/#{field(payload, :client_user_id)}"
      })

  # ADR-104: a machine needs a repair, or a consumable is running out.
  def process_event("inventory_repair_needed", payload),
    do:
      enqueue_simple(:inventory_repair_needed, payload, %{
        machine_id: field(payload, :machine_id),
        machine_name: field(payload, :machine_name),
        kind: field(payload, :kind),
        severity: field(payload, :severity),
        symptom: field(payload, :symptom),
        body: field(payload, :body),
        url: "/admin/inventory?tab=machines"
      })

  def process_event("inventory_stock_low", payload),
    do:
      enqueue_simple(:inventory_stock_low, payload, %{
        supply_id: field(payload, :supply_id),
        supply_name: field(payload, :supply_name),
        status: field(payload, :status),
        quantity: field(payload, :quantity),
        days_left: field(payload, :days_left),
        note: field(payload, :note),
        level: field(payload, :level),
        place: field(payload, :place),
        url: "/admin/inventory?tab=supplies"
      })

  def process_event("inventory_digest", payload),
    do:
      enqueue_simple(:inventory_digest, payload, %{
        date: field(payload, :date),
        reported_low: field(payload, :reported_low),
        low_stock: field(payload, :low_stock),
        critical_stock: field(payload, :critical_stock),
        service_due: field(payload, :service_due),
        service_soon: field(payload, :service_soon),
        machines_down: field(payload, :machines_down),
        machine_notes: field(payload, :machine_notes),
        highlights: field(payload, :highlights),
        url: "/admin/inventory"
      })

  def process_event(_event, _payload), do: {:error, :bad_request}

  def propagate_nickname_change(old_nickname, new_nickname),
    do: NotificationStore.propagate_nickname_change(old_nickname, new_nickname)

  def enqueue_admins_new_booking(booking),
    do: enqueue_for_users(staff_recipients(booking), :booking_pending, booking)

  def enqueue_member_booking_approved(booking),
    do: enqueue_for_users([%{id: field(booking, :user_id)}], :booking_approved, booking)

  def enqueue_member_booking_rejected(booking),
    do: enqueue_for_users([%{id: field(booking, :user_id)}], :booking_rejected, booking)

  def enqueue_booking_timeout_alert(booking),
    do: enqueue_for_users(staff_recipients(booking), :booking_timeout, booking)

  def enqueue_workout_note(note_payload) do
    note_payload
    |> staff_recipients()
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

  def enqueue_chat_message(payload) when is_map(payload) do
    user_id = field(payload, :user_id)

    payload =
      payload
      |> Map.put_new(
        :dedupe_key,
        field(payload, :dedupe_key) || "chat-message:#{field(payload, :message_id)}"
      )
      |> Map.put_new(:url, "/account/activity/chats?thread=#{field(payload, :thread_id)}")

    case deliver_notification(user_id, :chat_message, payload) do
      {:ok, _notification} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, reason}
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

    payload
    |> staff_recipients()
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

    payload
    |> staff_recipients()
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

    payload
    |> staff_recipients()
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

    payload
    |> field(:admin_ids)
    |> case do
      nil -> {:error, :organization_context_required}
      admin_ids -> List.wrap(admin_ids)
    end
    |> case do
      {:error, reason} ->
        {:error, reason}

      admin_ids ->
        admin_ids
        |> Enum.uniq()
        |> Enum.reduce_while(:ok, fn admin_id, :ok ->
          result =
            deliver_notification(admin_id, :workout_assignment_requested, %{
              organization_id: field(payload, :organization_id),
              athlete_id: athlete_id,
              athlete_nickname: athlete_nickname,
              requested_for: requested_for,
              note: note,
              dedupe_key: "workout-assignment-requested:#{admin_id}:#{dedupe_id}",
              url: url
            })

          if delivered?(result), do: {:cont, :ok}, else: {:halt, result}
        end)
    end
  end

  def enqueue_review_submitted(payload) when is_map(payload) do
    review_id = field(payload, :review_id)

    payload
    |> staff_recipients()
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

  # ADR-097 notifications with a fixed payload shape.
  defp enqueue_simple(type, payload, notification_payload) do
    user_id = field(payload, :user_id)

    case deliver_notification(user_id, type, stringify_values(notification_payload)) do
      {:ok, _notification} ->
        :ok

      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error("#{type} delivery failed user_id=#{user_id} reason=#{inspect(reason)}")
        error
    end
  end

  defp stringify_values(payload) do
    Map.new(payload, fn
      {key, %DateTime{} = value} ->
        {key, DateTime.to_iso8601(value)}

      {key, %Date{} = value} ->
        {key, Date.to_iso8601(value)}

      {key, value} when is_atom(value) and not is_nil(value) and not is_boolean(value) ->
        {key, Atom.to_string(value)}

      pair ->
        pair
    end)
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
    user_id = Map.get(params, :user_id) || Map.get(params, "user_id")

    case NotificationStore.with_user_context(%{user_id: user_id}, fn ->
           MilosTraining.Notifications.Commands.CreateNotification.call(params)
         end) do
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

  defp staff_recipients(payload) do
    case field(payload, :organization_id) do
      organization_id when is_binary(organization_id) ->
        organization_id
        |> Organizations.list_staff_user_ids()
        |> Enum.map(&%{id: &1})

      _missing ->
        []
    end
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
