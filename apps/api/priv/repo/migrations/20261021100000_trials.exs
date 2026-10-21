defmodule Palee.Repo.Migrations.Trials do
  use Ecto.Migration

  # ADR-144 (P2-M3): a person who is not a member tries a class, inside the
  # limits the owner sets. The Trials context owns the owner's policy and the
  # funnel (scheduling_trial_requests); Scheduling owns the seat, a booking of
  # kind 'trial' that draws no package allowance ('none').

  @notification_types ~w(
    booking_approved booking_rejected booking_pending booking_timeout workout_note
    workout_changed workout_deleted workout_rejected workout_moved workout_assigned
    workout_assignment_requested review_submitted athlete_message workout_completed
    coaching_message box_message challenge_completed chat_message invoice_issued
    payment_reminder booking_waitlist_promoted package_expiring form_review_submitted
    form_review_completed coaching_reply_overdue nutrition_plan_updated appointment_booked
    appointment_cancelled coach_client_assigned coach_note_viewed inventory_repair_needed
    inventory_stock_low inventory_digest subscription_expiring subscription_grace access_ended
    follow_requested follow_accepted
  )

  @trial_notification_types ~w(
    trial_requested trial_booked trial_cancelled trial_accepted trial_declined
    trial_reminder trial_follow_up trial_class_cancelled
  )

  def up do
    replace_notification_types(@notification_types ++ @trial_notification_types)

    # Bookings say what they are instead of inferring it from guest_name.
    alter table(:bookings) do
      add :kind, :string, null: false, default: "member"
    end

    execute("UPDATE bookings SET kind = 'guest' WHERE guest_name IS NOT NULL")

    create constraint(:bookings, :bookings_kind_check,
             check: "kind IN ('member', 'guest', 'trial')"
           )

    drop constraint(:bookings, :bookings_entitlement_allowance)

    create constraint(:bookings, :bookings_entitlement_allowance,
             check:
               "entitlement_allowance IN ('class_visits', 'event_visits', 'guest_passes', 'none')"
           )

    # A trial seat never touches a package; nothing else may skip the ledger.
    create constraint(:bookings, :bookings_trial_allowance_check,
             check: "(kind = 'trial') = (entitlement_allowance = 'none')"
           )

    create index(:bookings, [:scheduled_class_id],
             where: "kind = 'trial' AND status IN ('pending', 'approved')",
             name: :bookings_active_trials_index
           )

    create table(:scheduling_trial_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :enabled, :boolean, null: false, default: false
      add :approval, :string, null: false, default: "auto"
      # Trials whose class falls in one week (Monday-Sunday, the box's time
      # zone), for the whole box; nil means no weekly limit.
      add :weekly_limit, :integer
      add :per_person_limit, :integer, null: false, default: 1
      add :seats_per_class, :integer, null: false, default: 2
      # Empty means every class type.
      add :class_type_ids, {:array, :binary_id}, null: false, default: []
      # How far ahead a trial can be booked; nil means as far as the schedule goes.
      add :horizon_days, :integer
      add :first_timers_only, :boolean, null: false, default: false
      add :no_show_consumes, :boolean, null: false, default: false
      add :bring_note, :text
      # Board 6 Q6: the package the box offers people who join after a trial.
      add :conversion_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:scheduling_trial_policies, [:organization_id])

    create constraint(:scheduling_trial_policies, :trial_policy_approval_check,
             check: "approval IN ('auto', 'manual')"
           )

    create constraint(:scheduling_trial_policies, :trial_policy_limits_check,
             check: """
             (weekly_limit IS NULL OR weekly_limit BETWEEN 1 AND 500)
             AND per_person_limit BETWEEN 1 AND 10
             AND seats_per_class BETWEEN 1 AND 50
             AND (horizon_days IS NULL OR horizon_days BETWEEN 1 AND 90)
             """
           )

    create table(:scheduling_trial_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Plain ids, not foreign keys: a withdrawn seat's booking row and a
      # deleted class disappear, while the trial keeps its history and the
      # reactions to those facts still find it by id.
      add :scheduled_class_id, :binary_id
      add :booking_id, :binary_id
      add :status, :string, null: false
      add :note, :text
      # Board 6 Q1: an optional number the box may call.
      add :phone, :string
      # Where the person came from (box_page, schedule, qr_door, referral…).
      add :source, :string, null: false, default: "box_page"
      add :client_operation_id, :binary_id
      add :class_starts_at, :utc_datetime_usec, null: false
      # The class as it was when asked, so the trial reads right after it is gone.
      add :class_name, :string
      add :decided_at, :utc_datetime_usec
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decline_reason, :text
      add :attended_at, :utc_datetime_usec
      add :converted_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec

      # Board 6 Q6: «Θέλω να γραφτώ» opened a chat with the box, or «Όχι τώρα».
      add :join_interest_at, :utc_datetime_usec
      add :follow_up_dismissed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:scheduling_trial_requests, :trial_request_status_check,
             check: """
             status IN ('requested', 'booked', 'declined', 'cancelled', 'expired',
                        'attended', 'no_show', 'converted')
             """
           )

    create index(:scheduling_trial_requests, [:organization_id, :status, :class_starts_at])
    create index(:scheduling_trial_requests, [:user_id, :class_starts_at])
    create index(:scheduling_trial_requests, [:organization_id, :user_id])
    create index(:scheduling_trial_requests, [:scheduled_class_id])

    create unique_index(:scheduling_trial_requests, [:booking_id],
             where: "booking_id IS NOT NULL"
           )

    create unique_index(:scheduling_trial_requests, [:user_id, :client_operation_id],
             where: "client_operation_id IS NOT NULL",
             name: :trial_requests_operation_index
           )

    # One open trial per person per box at a time.
    create unique_index(:scheduling_trial_requests, [:organization_id, :user_id],
             where: "status IN ('requested', 'booked')",
             name: :trial_requests_one_open_index
           )

    org = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"
    me = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY scheduling_trial_policies_tenant_policy ON scheduling_trial_policies
    FOR ALL USING (#{org}) WITH CHECK (#{org})
    """)

    # The box sees and handles its trials; the person sees their own, at any box.
    execute("""
    CREATE POLICY scheduling_trial_requests_tenant_policy ON scheduling_trial_requests
    FOR ALL USING (#{org}) WITH CHECK (#{org})
    """)

    execute("""
    CREATE POLICY scheduling_trial_requests_owner_read_policy ON scheduling_trial_requests
    FOR SELECT USING (#{me})
    """)

    for table <- ~w(scheduling_trial_policies scheduling_trial_requests) do
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # Board 6 Q6: a person talks to a box they are not a member of (yet) from
    # its page. Messaging stays tenant-scoped; this narrow helper only says at
    # which boxes the signed-in person (app.user_id, never a parameter) has
    # their own conversation, and each is then read in that box's scope.
    execute("""
    CREATE OR REPLACE FUNCTION palee_my_box_conversation_organization_ids()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT DISTINCT t.organization_id
      FROM public.messaging_threads t
      JOIN public.messaging_participants p
        ON p.thread_id = t.id AND p.user_id = t.context_id
      WHERE t.context_type = 'box'
        AND t.context_id = NULLIF(current_setting('app.user_id', true), '')::uuid
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_my_box_conversation_organization_ids()")
    replace_notification_types(@notification_types)
    drop table(:scheduling_trial_requests)
    drop table(:scheduling_trial_policies)
    drop index(:bookings, [:scheduled_class_id], name: :bookings_active_trials_index)
    drop constraint(:bookings, :bookings_trial_allowance_check)
    drop constraint(:bookings, :bookings_entitlement_allowance)

    create constraint(:bookings, :bookings_entitlement_allowance,
             check: "entitlement_allowance IN ('class_visits', 'event_visits', 'guest_passes')"
           )

    drop constraint(:bookings, :bookings_kind_check)

    alter table(:bookings) do
      remove :kind
    end
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end
end
