defmodule MilosTraining.Notifications do
  require Logger

  alias MilosTraining.{Identity, Organizations}
  alias MilosTraining.Notifications.Commands.DeleteNativePushToken
  alias MilosTraining.Notifications.Commands.DeletePushSubscription
  alias MilosTraining.Notifications.Commands.DispatchNotification
  alias MilosTraining.Notifications.Commands.EnqueueNotificationEvent
  alias MilosTraining.Notifications.Commands.MarkAllRead
  alias MilosTraining.Notifications.Commands.MarkNotificationRead
  alias MilosTraining.Notifications.Commands.SaveNativePushToken
  alias MilosTraining.Notifications.Commands.SavePushSubscription
  alias MilosTraining.Notifications.Domain.NotificationDedupe
  alias MilosTraining.Notifications.NativePush
  alias MilosTraining.Notifications.NativePushTokenStore
  alias MilosTraining.Notifications.PushConfig
  alias MilosTraining.Notifications.Queries.ListNativePushTokens
  alias MilosTraining.Notifications.Queries.GetUnreadCount
  alias MilosTraining.Notifications.Queries.ListInboxPage
  alias MilosTraining.Notifications.Queries.GetPushSubscriptionStatus
  alias MilosTraining.Notifications.Queries.ListPushSubscriptions
  alias MilosTraining.Notifications.NotificationStore
  alias MilosTraining.Notifications.PushSubscriptionStore
  alias MilosTraining.Notifications.Queries.ListNotifications

  @community_types ~w(
    community_group_proposed community_group_approved community_group_declined
    community_group_join_requested community_group_join_approved community_group_archive_warning
    community_report_created community_club_join_requested community_club_join_approved
  )

  @event_types ~w(
    community_event_waitlist_promoted community_event_cancelled community_event_changed
    community_event_reminder community_event_guest_joined community_event_trial_offer
    community_event_message
  )

  @referral_types ~w(referral_progress referral_reward referral_review)

  @season_types ~w(season_requested season_confirmed season_declined season_cancelled)

  def create_notification(params), do: create_and_broadcast_notification(params)

  # ADR-123: push dispatch result -> {outcome, reason_class} for analytics.
  defdelegate classify_push_outcome(result),
    to: MilosTraining.Notifications.Domain.PushDeliveryOutcome,
    as: :classify

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
      vapid_public_key: PushConfig.public_key(),
      native_providers: NativePush.configured_providers()
    }
  end

  # ADR-171: push to the store apps (FCM on Android, APNs on iOS).

  @doc """
  Registers a store app install's push token for the person. Answers
  `{:error, :native_push_not_configured}` while the provider has no
  credentials, so nothing is stored that could not be used.
  """
  def register_native_push_token(user_id, attrs) when is_map(attrs) do
    provider = attr(attrs, :provider)

    if NativePush.configured?(provider) do
      NativePushTokenStore.with_user_context(%{user_id: user_id}, fn ->
        SaveNativePushToken.call(%{
          user_id: user_id,
          provider: provider,
          platform: attr(attrs, :platform),
          token: attr(attrs, :token),
          app_id: attr(attrs, :app_id),
          app_version: attr(attrs, :app_version),
          apns_environment:
            if(provider == "apns", do: attr(attrs, :apns_environment) || "production"),
          last_registered_at: DateTime.utc_now()
        })
      end)
    else
      {:error, :native_push_not_configured}
    end
  end

  def list_native_push_tokens(user_id),
    do:
      NativePushTokenStore.with_user_context(%{user_id: user_id}, fn ->
        ListNativePushTokens.call(user_id)
      end)

  def get_native_push_token(user_id, id),
    do:
      NativePushTokenStore.with_user_context(%{user_id: user_id}, fn ->
        ListNativePushTokens.get(user_id, id)
      end)

  def delete_native_push_token(user_id, token) when is_binary(token),
    do:
      NativePushTokenStore.with_user_context(%{user_id: user_id}, fn ->
        DeleteNativePushToken.call(user_id, token)
      end)

  def delete_native_push_token_by_id(user_id, id),
    do:
      NativePushTokenStore.with_user_context(%{user_id: user_id}, fn ->
        DeleteNativePushToken.by_id(user_id, id)
      end)

  defp attr(attrs, key) do
    case Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) do
      value when is_binary(value) -> String.trim(value)
      _other -> nil
    end
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

  def process_event("coaching_message", payload),
    do: enqueue_message_to_member(:coaching_message, payload)

  def process_event("box_message", payload), do: enqueue_message_to_member(:box_message, payload)
  def process_event("challenge_completed", payload), do: enqueue_challenge_completed(payload)

  # ADR-142: follows of people.
  def process_event("follow_requested", payload),
    do:
      enqueue_simple(:follow_requested, payload, %{
        follow_id: field(payload, :follow_id),
        follower_id: field(payload, :follower_id),
        follower_nickname: field(payload, :follower_nickname),
        dedupe_key: "follow_requested:#{field(payload, :follow_id)}",
        url: "/me/follow-requests"
      })

  def process_event("follow_accepted", payload),
    do:
      enqueue_simple(:follow_accepted, payload, %{
        follow_id: field(payload, :follow_id),
        person_id: field(payload, :person_id),
        person_nickname: field(payload, :person_nickname),
        dedupe_key: "follow_accepted:#{field(payload, :follow_id)}",
        url: "/people/#{field(payload, :person_id)}"
      })

  # ADR-144: trials. Staff hear about new and cancelled trials; the person
  # hears the box's answer, a reminder before the class and a follow-up after.
  def process_event(type, payload)
      when type in ~w(trial_requested trial_booked trial_cancelled) do
    organization_id = field(payload, :organization_id)

    organization_id
    |> Organizations.list_staff_user_ids()
    |> Enum.reduce_while(:ok, fn staff_id, :ok ->
      case enqueue_simple(
             String.to_existing_atom(type),
             %{user_id: staff_id},
             trial_payload(type, payload, "staff:#{staff_id}", "/admin/trials")
           ) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def process_event(type, payload)
      when type in ~w(trial_accepted trial_declined trial_reminder trial_follow_up trial_class_cancelled),
      do:
        enqueue_simple(
          String.to_existing_atom(type),
          payload,
          trial_payload(type, payload, "person", "/trials/#{field(payload, :trial_id)}")
        )

  # ADR-143: member groups, open clubs and reports. Each event names its one
  # recipient; the use case fans out to staff or a group's admins.
  def process_event(type, payload) when type in @community_types,
    do:
      enqueue_simple(
        String.to_existing_atom(type),
        payload,
        community_payload(type, payload)
      )

  # ADR-153: club events. Each event names its one recipient; the use case
  # fans out to the people going.
  def process_event(type, payload) when type in @event_types,
    do:
      enqueue_simple(
        String.to_existing_atom(type),
        payload,
        event_payload(type, payload)
      )

  # ADR-156: invites. The inviter hears each friend's step and their reward;
  # the box's owners and admins hear a referral waiting for approval.
  def process_event(type, payload) when type in @referral_types,
    do:
      enqueue_simple(
        String.to_existing_atom(type),
        payload,
        referral_payload(type, payload)
      )

  # ADR-167: seasons. Each event names its one recipient; the use case fans a
  # request out to the staff who confirm places and the season's coaches.
  def process_event(type, payload) when type in @season_types,
    do:
      enqueue_simple(
        String.to_existing_atom(type),
        payload,
        season_payload(type, payload)
      )

  # ADR-154: a saved Γύρω μου filter found something new (at most daily).
  def process_event("around_new_matches", payload),
    do:
      enqueue_simple(:around_new_matches, payload, %{
        filter_id: field(payload, :filter_id),
        filter_name: field(payload, :filter_name),
        count: field(payload, :count),
        dedupe_key: field(payload, :dedupe_key),
        url: "/around?filter=#{field(payload, :filter_id)}"
      })

  # ADR-158: the opt-in reminder to take a new body measurement.
  def process_event("body_measure_reminder", payload),
    do:
      enqueue_simple(:body_measure_reminder, payload, %{
        weeks: field(payload, :weeks),
        dedupe_key: field(payload, :dedupe_key),
        url: "/journal/body/new"
      })

  # ADR-160: Buddy για στήριξη. Leaving or declining sends nothing.
  def process_event("buddy_invite", payload),
    do:
      enqueue_simple(:buddy_invite, payload, %{
        link_id: field(payload, :link_id),
        inviter_id: field(payload, :inviter_id),
        nickname: field(payload, :inviter_nickname),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/buddies"
      })

  def process_event("buddy_accepted", payload),
    do:
      enqueue_simple(:buddy_accepted, payload, %{
        link_id: field(payload, :link_id),
        buddy_id: field(payload, :buddy_id),
        nickname: field(payload, :buddy_nickname),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/buddies"
      })

  # Inside the buddy's quiet hours it lands in the inbox without a push.
  def process_event("support_request", payload),
    do:
      enqueue_simple(:support_request, payload, %{
        request_id: field(payload, :request_id),
        sender_id: field(payload, :sender_id),
        nickname: field(payload, :sender_nickname),
        message: field(payload, :message),
        quick_replies: field(payload, :quick_replies) || [],
        silent: field(payload, :silent) == true,
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/support-requests/#{field(payload, :request_id)}"
      })

  def process_event("support_reply", payload),
    do:
      enqueue_simple(:support_reply, payload, %{
        request_id: field(payload, :request_id),
        reply_id: field(payload, :reply_id),
        buddy_id: field(payload, :buddy_id),
        nickname: field(payload, :buddy_nickname),
        kind: field(payload, :kind),
        text: field(payload, :text),
        link_id: field(payload, :link_id),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/support-requests/#{field(payload, :request_id)}"
      })

  # ADR-160 §2: a message in the pair's buddy conversation. The push names
  # who wrote, never what.
  def process_event("buddy_message", payload),
    do:
      enqueue_simple(:buddy_message, payload, %{
        link_id: field(payload, :link_id),
        message_id: field(payload, :message_id),
        author_id: field(payload, :author_id),
        nickname: field(payload, :author_nickname),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/buddies/#{field(payload, :link_id)}/messages"
      })

  # ADR-169: a mutual like in a club; a message in the pair's conversation
  # (the push names who wrote, never what).
  def process_event("partner_match", payload),
    do:
      enqueue_simple(:partner_match, payload, %{
        match_id: field(payload, :match_id),
        club_id: field(payload, :club_id),
        club_name: field(payload, :club_name),
        nickname: field(payload, :partner_nickname),
        dedupe_key: field(payload, :dedupe_key),
        url: "/partners/#{field(payload, :match_id)}"
      })

  def process_event("partner_message", payload),
    do:
      enqueue_simple(:partner_message, payload, %{
        match_id: field(payload, :match_id),
        message_id: field(payload, :message_id),
        author_id: field(payload, :author_id),
        nickname: field(payload, :author_nickname),
        dedupe_key: field(payload, :dedupe_key),
        url: "/partners/#{field(payload, :match_id)}"
      })

  # ADR-160 §4: the coach's Sunday wellness summary of a client who shares
  # it. Counts only; the craving moments stay on the client page.
  def process_event("coach_wellness_summary", payload),
    do:
      enqueue_simple(:coach_wellness_summary, payload, %{
        organization_id: field(payload, :organization_id),
        client_user_id: field(payload, :client_user_id),
        client_nickname: field(payload, :client_nickname),
        week_start: field(payload, :week_start),
        week_end: field(payload, :week_end),
        sleep_nights: field(payload, :sleep_nights),
        water_days: field(payload, :water_days),
        meal_days: field(payload, :meal_days),
        dedupe_key: field(payload, :dedupe_key),
        url: "/admin/users/#{field(payload, :client_user_id)}"
      })

  def process_event("support_no_reply_nudge", payload),
    do:
      enqueue_simple(:support_no_reply_nudge, payload, %{
        request_id: field(payload, :request_id),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/support-requests/#{field(payload, :request_id)}"
      })

  # Counts only, never times, causes or foods.
  def process_event("buddy_weekly_summary", payload),
    do:
      enqueue_simple(:buddy_weekly_summary, payload, %{
        member_id: field(payload, :member_id),
        nickname: field(payload, :member_nickname),
        week_start: field(payload, :week_start),
        week_end: field(payload, :week_end),
        hard_moments: field(payload, :hard_moments),
        overcome: field(payload, :overcome),
        support_requests: field(payload, :support_requests),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/buddies"
      })

  # ADR-159 (board 14, Q6): «Πώς πήγε;» once for a craving left open. The
  # push never names the craving; the page does, once unlocked.
  def process_event("craving_follow_up", payload),
    do:
      enqueue_simple(:craving_follow_up, payload, %{
        craving_id: field(payload, :craving_id),
        dedupe_key: field(payload, :dedupe_key),
        url: "/journal/wellbeing?craving=#{field(payload, :craving_id)}"
      })

  # ADR-162 (board 17 extra): the whole-journal export is ready to download.
  def process_event("journal_export_ready", payload),
    do:
      enqueue_simple(:journal_export_ready, payload, %{
        export_id: field(payload, :export_id),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/settings/export"
      })

  # ADR-161 (board 16, Q6): a device stopped syncing; once per spell.
  def process_event("device_sync_error", payload),
    do:
      enqueue_simple(:device_sync_error, payload, %{
        provider: field(payload, :provider),
        dedupe_key: field(payload, :dedupe_key),
        url: "/me/devices"
      })

  # ADR-159 (board 14, Q2): the opt-in afternoon water reminder.
  def process_event("water_reminder", payload),
    do:
      enqueue_simple(:water_reminder, payload, %{
        dedupe_key: field(payload, :dedupe_key),
        url: "/journal/wellbeing"
      })

  # ADR-155 (board 10, Q3): a person who is not a member scanned the door.
  # Staff who check people in hear about it, so the desk can follow up and
  # sell a walk-in or a trial; the caller keeps it to once an hour per
  # person and box, and the dedupe key holds that per staff member too.
  def process_event("check_in_visitor", payload) do
    organization_id = field(payload, :organization_id)
    visitor_id = field(payload, :visitor_id)

    organization_id
    |> Organizations.list_user_ids_with_capability(:check_in)
    |> Enum.reduce_while(:ok, fn staff_id, :ok ->
      case enqueue_simple(:check_in_visitor, %{user_id: staff_id}, %{
             organization_id: organization_id,
             scan_id: field(payload, :scan_id),
             visitor_id: visitor_id,
             person_nickname: field(payload, :person_nickname),
             box_name: field(payload, :box_name),
             location_name: field(payload, :location_name),
             scanned_at: field(payload, :scanned_at),
             scanned_when: field(payload, :scanned_when),
             trial_available: field(payload, :trial_available) in [true, "true"],
             dedupe_key:
               "check_in_visitor:#{organization_id}:#{visitor_id}:#{field(payload, :hour)}:#{staff_id}",
             url: field(payload, :url) || "/admin/check-in"
           }) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

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

  def process_event("subscription_expiring", payload),
    do: enqueue_subscription_notice(:subscription_expiring, payload)

  def process_event("subscription_grace", payload),
    do: enqueue_subscription_notice(:subscription_grace, payload)

  def process_event("access_ended", payload),
    do: enqueue_subscription_notice(:access_ended, payload)

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

  @doc """
  A coaching message or a message from the box reached a member (ADR-140
  §6): unlike chat, it shows in the member's inbox.
  """
  def enqueue_message_to_member(type, payload)
      when type in [:coaching_message, :box_message] and is_map(payload) do
    user_id = field(payload, :user_id)

    payload =
      payload
      |> Map.put_new(:dedupe_key, "#{type}:#{field(payload, :message_id)}")
      |> Map.put_new(:url, "/account/activity/chats?thread=#{field(payload, :thread_id)}")

    case deliver_notification(user_id, type, payload) do
      {:ok, _notification} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, reason}
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

        # Assignments are normalized with ISO-8601 string dates (and job args
        # are JSON), so accept both a Date and its string form.
        date ->
          "/admin/coaching-assignments?open_assignment=#{assigned_workout_id}&date=#{iso_date(date)}"
      end

    payload
    |> staff_recipients()
    |> Enum.each(fn admin ->
      result =
        deliver_notification(admin.id, :workout_rejected, %{
          organization_id: field(payload, :organization_id),
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

  defp iso_date(%Date{} = date), do: Date.to_iso8601(date)
  defp iso_date(date) when is_binary(date), do: date

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

  defp trial_payload(type, payload, audience, default_url) do
    trial_id = field(payload, :trial_id)

    %{
      organization_id: field(payload, :organization_id),
      trial_id: trial_id,
      person_nickname: field(payload, :person_nickname),
      box_name: field(payload, :box_name),
      class_name: field(payload, :class_name),
      class_starts_at: field(payload, :class_starts_at),
      class_when: field(payload, :class_when),
      decline_reason: field(payload, :decline_reason),
      dedupe_key: "#{type}:#{trial_id}:#{audience}",
      url: field(payload, :url) || default_url
    }
  end

  defp community_payload(type, payload) do
    club_id = field(payload, :club_id)
    group_id = field(payload, :group_id)

    {dedupe, url} =
      case type do
        "community_group_proposed" ->
          {group_id, "/admin/community"}

        "community_group_declined" ->
          {group_id, "/clubs/#{club_id}"}

        "community_group_join_requested" ->
          {"#{group_id}:#{field(payload, :person_id)}", "/clubs/#{club_id}/groups/#{group_id}"}

        "community_group_archive_warning" ->
          {"#{group_id}:#{field(payload, :warned_on)}", "/clubs/#{club_id}/groups/#{group_id}"}

        "community_report_created" ->
          {"#{field(payload, :target_type)}:#{field(payload, :target_id)}",
           "/admin/community?tab=reports"}

        "community_club_join_requested" ->
          {"#{club_id}:#{field(payload, :person_id)}", "/admin/community?tab=clubs"}

        "community_club_join_approved" ->
          {club_id, "/clubs/#{club_id}"}

        _group_answer ->
          {group_id, "/clubs/#{club_id}/groups/#{group_id}"}
      end

    %{
      organization_id: field(payload, :organization_id),
      club_id: club_id,
      club_name: field(payload, :club_name),
      group_id: group_id,
      group_name: field(payload, :group_name),
      person_nickname: field(payload, :person_nickname),
      target_type: field(payload, :target_type),
      reason: field(payload, :reason),
      dedupe_key: "#{type}:#{dedupe}",
      url: url
    }
  end

  defp season_payload(type, payload) do
    season_id = field(payload, :season_id)

    url =
      if type == "season_requested",
        do: "/admin/finance?tab=seasons&season=#{season_id}",
        else: "/box?season=#{season_id}"

    %{
      organization_id: field(payload, :organization_id),
      season_id: season_id,
      season_title: field(payload, :season_title),
      starts_on: field(payload, :starts_on),
      person_nickname: field(payload, :person_nickname),
      box_name: field(payload, :box_name),
      enrollment_status: field(payload, :enrollment_status),
      reason: field(payload, :reason),
      dedupe_key: "#{type}:#{season_id}:#{field(payload, :enrollment_id)}:#{field(payload, :at)}",
      url: url
    }
  end

  defp event_payload(type, payload) do
    event_id = field(payload, :event_id)

    %{
      organization_id: field(payload, :organization_id),
      club_id: field(payload, :club_id),
      event_id: event_id,
      event_title: field(payload, :event_title),
      event_starts_at: field(payload, :event_starts_at),
      event_when: field(payload, :event_when),
      changes: field(payload, :changes),
      reason: field(payload, :reason),
      person_nickname: field(payload, :person_nickname),
      box_name: field(payload, :box_name),
      message: field(payload, :message),
      dedupe_key: "#{type}:#{event_id}:#{field(payload, :dedupe)}",
      url: field(payload, :url) || "/events/#{event_id}"
    }
  end

  # ADR-156: the member's notices open «Φέρε φίλο» › «Οι προσκλήσεις σου»
  # at that box (board 11 Q2 B); staff's open the Finance › Συστάσεις queue.
  defp referral_payload(type, payload) do
    attribution_id = field(payload, :attribution_id)
    box = field(payload, :box) || %{}
    box_slug = field(box, :box_slug)

    mine =
      if box_slug,
        do: "/me/referrals?tab=invites&box=#{URI.encode_www_form(box_slug)}",
        else: "/me/referrals?tab=invites"

    {dedupe, url} =
      case type do
        "referral_progress" -> {"#{attribution_id}:#{field(payload, :stage)}", mine}
        "referral_reward" -> {"#{attribution_id}:#{field(payload, :reward_status)}", mine}
        "referral_review" -> {attribution_id, "/admin/finance?tab=referrals"}
      end

    %{
      organization_id: field(payload, :organization_id),
      attribution_id: attribution_id,
      stage: field(payload, :stage),
      reward_status: field(payload, :reward_status),
      person_nickname: field(payload, :person_nickname),
      referrer_nickname: field(payload, :referrer_nickname),
      box_name: field(box, :box_name),
      box_slug: box_slug,
      dedupe_key: "#{type}:#{dedupe}",
      url: field(payload, :url) || url
    }
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

  # Sent to the client whose subscription ends; deduplicated per subscription
  # so a retried job never notifies twice.
  def enqueue_subscription_notice(type, payload) when is_map(payload) do
    user_id = field(payload, :user_id)

    notification_payload =
      payload
      |> Map.take([
        :package_name,
        :ends_on,
        :days_left,
        :grace_days,
        :grace_until,
        :reason,
        :cancelled_bookings
      ])
      |> Map.merge(%{
        url: "/account/billing",
        dedupe_key: dedupe_key(type, payload)
      })

    case deliver_notification(user_id, type, notification_payload) do
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

  # Access can be lost more than once per membership (renew, lapse again), so
  # that notice is unique per day rather than per subscription.
  defp dedupe_key(:access_ended, payload),
    do: "access_ended:#{field(payload, :membership_id)}:#{Date.utc_today()}"

  defp dedupe_key(type, payload), do: "#{type}:#{field(payload, :subscription_id)}"

  @doc """
  Removes the staff's `booking_pending` notifications for a booking that is no
  longer pending (withdrawn by the member).

  TD-092: notifications are owner-only under RLS, so a delete issued in the
  member's (or a job's) session never reached the staff's rows. The staff of
  the booking's organization are resolved server-side and each recipient's
  rows are removed in that recipient's own scope, limited to the organization.
  """
  def delete_booking_pending_notifications(organization_id, booking_id)
      when is_binary(organization_id) do
    organization_id
    |> Organizations.list_staff_user_ids()
    |> Enum.reduce_while(:ok, fn staff_id, :ok ->
      case NotificationStore.with_user_context(
             %{organization_id: organization_id, user_id: staff_id},
             fn -> NotificationStore.delete_booking_pending_for_booking(booking_id) end
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def delete_booking_pending_notifications(_organization_id, _booking_id), do: :ok

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
      # TD-092: tenant provenance, so the row can be found again in the
      # organization's scope (pending-notice cleanup) and push links are org-scoped.
      organization_id: field(booking, :organization_id),
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
        emit_delivered(notification)
        ok

      {:error, {:push_enqueue_failed, notification, _reason}} = error ->
        broadcast_notification_changed(notification.user_id)
        emit_delivered(notification)
        error

      {:error, _reason} = error ->
        error
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

  # ADR-123: a new in-app notification row is the in-app delivery. Emitted as
  # telemetry (not a call into Analytics) so this context stays independent;
  # MilosTraining.Application.RecordNotificationDelivered records it.
  defp emit_delivered(notification) do
    :telemetry.execute([:milos, :notification, :delivered], %{count: 1}, %{
      notification_id: notification.id,
      user_id: notification.user_id,
      organization_id: Map.get(notification, :organization_id),
      type: Map.get(notification, :type),
      channel: "in_app"
    })
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
            emit_delivered(notification)
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

  defp challenge_completed_dedupe_key(user_id, payload) do
    NotificationDedupe.challenge_completed_key(user_id, field(payload, :challenge_id))
  end

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Notifications.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
