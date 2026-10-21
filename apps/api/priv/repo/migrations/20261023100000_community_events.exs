defmodule Palee.Repo.Migrations.CommunityEvents do
  use Ecto.Migration

  # ADR-153 (P2-M5): events per club.
  #
  # - community_events: one row per occurrence. A weekly repeat is a run of
  #   rows sharing series_id, each with its own attendee list. The event's
  #   card in the club feed is a community_posts row (attachment_type 'event')
  #   whose id every occurrence of the series keeps in post_id.
  # - community_event_attendees: who said «Θα έρθω» (going), who waits
  #   (waitlisted) and who withdrew (cancelled); members of the club, anyone
  #   signed in on an open event, and guests a going member invited. One row
  #   per person and event: changing your mind updates it.
  # - scheduling_trial_requests.referral_event_id: the community event whose
  #   trial offer a trial request came from (a plain id, like the class).

  @before_types ~w(
    booking_approved booking_rejected booking_pending booking_timeout workout_note
    workout_changed workout_deleted workout_rejected workout_moved workout_assigned
    workout_assignment_requested review_submitted athlete_message workout_completed
    coaching_message box_message challenge_completed chat_message invoice_issued
    payment_reminder booking_waitlist_promoted package_expiring form_review_submitted
    form_review_completed coaching_reply_overdue nutrition_plan_updated appointment_booked
    appointment_cancelled coach_client_assigned coach_note_viewed inventory_repair_needed
    inventory_stock_low inventory_digest subscription_expiring subscription_grace access_ended
    follow_requested follow_accepted trial_requested trial_booked trial_cancelled
    trial_accepted trial_declined trial_reminder trial_follow_up trial_class_cancelled
    community_group_proposed community_group_approved community_group_declined
    community_group_join_requested community_group_join_approved community_group_archive_warning
    community_report_created community_club_join_requested community_club_join_approved
  )

  @event_types ~w(
    community_event_waitlist_promoted community_event_cancelled community_event_changed
    community_event_reminder community_event_guest_joined community_event_trial_offer
    community_event_message
  )

  @attachments_before ~w(training_log_entry workout_execution pr)

  def up do
    create table(:community_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, :binary_id, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :title, :string, null: false
      add :description, :text
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec, null: false

      # Where: one of the box's locations, or a place of its own.
      add :location_id,
          references(:facility_locations, type: :binary_id, on_delete: :nilify_all)

      add :place_name, :string
      add :address, :string
      add :latitude, :float
      add :longitude, :float

      # Nil means no limit.
      add :capacity, :integer
      add :price_cents, :integer, null: false, default: 0
      add :currency, :string, null: false, default: "EUR"
      add :open_to_non_members, :boolean, null: false, default: false
      add :guest_pass_allowed, :boolean, null: false, default: false
      add :guests_per_member, :integer, null: false, default: 1
      # A box photo (ADR-148), like an open club's cover.
      add :cover_media_id, :binary_id
      add :series_id, :binary_id
      add :cancelled_at, :utc_datetime_usec
      add :cancel_reason, :string
      add :reminder_sent_at, :utc_datetime_usec
      add :trial_offer_sent_at, :utc_datetime_usec
      add :post_id, references(:community_posts, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    composite_fk(:community_events, :club_id, :community_clubs)

    create unique_index(:community_events, [:id, :organization_id],
             name: :community_events_id_organization_index
           )

    create constraint(:community_events, :community_events_title_check,
             check: "length(btrim(title)) BETWEEN 1 AND 120"
           )

    create constraint(:community_events, :community_events_description_check,
             check: "description IS NULL OR length(description) <= 4000"
           )

    create constraint(:community_events, :community_events_time_check,
             check: "ends_at > starts_at AND ends_at <= starts_at + interval '7 days'"
           )

    create constraint(:community_events, :community_events_place_check,
             check:
               "NOT (location_id IS NOT NULL AND place_name IS NOT NULL) AND " <>
                 "(latitude IS NULL) = (longitude IS NULL) AND " <>
                 "(latitude IS NULL OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180))"
           )

    create constraint(:community_events, :community_events_limits_check,
             check:
               "(capacity IS NULL OR capacity BETWEEN 1 AND 10000) AND " <>
                 "price_cents BETWEEN 0 AND 10000000 AND guests_per_member BETWEEN 1 AND 10 AND " <>
                 "currency ~ '^[A-Z]{3}$'"
           )

    create constraint(:community_events, :community_events_cancel_check,
             check:
               "(cancelled_at IS NOT NULL OR cancel_reason IS NULL) AND " <>
                 "(cancel_reason IS NULL OR length(cancel_reason) <= 300)"
           )

    create index(:community_events, [:organization_id, :starts_at])
    create index(:community_events, [:club_id, :starts_at])
    create index(:community_events, [:series_id, :starts_at], where: "series_id IS NOT NULL")
    create index(:community_events, [:post_id], where: "post_id IS NOT NULL")

    create index(:community_events, [:starts_at],
             where: "open_to_non_members AND cancelled_at IS NULL",
             name: :community_events_open_index
           )

    # The reminder sweep looks only at events that still owe one.
    create index(:community_events, [:starts_at],
             where: "reminder_sent_at IS NULL AND cancelled_at IS NULL",
             name: :community_events_reminder_due_index
           )

    create table(:community_event_attendees, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :source, :string, null: false
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # When the person took their current place: the waitlist runs in this order.
      add :queued_at, :utc_datetime_usec, null: false
      add :promoted_at, :utc_datetime_usec
      add :paid_at, :utc_datetime_usec
      add :paid_recorded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :payment_method, :string
      add :amount_cents, :integer
      # The receipt Finance issued for the payment, when it could (plain ids).
      add :finance_invoice_id, :binary_id
      add :finance_payment_id, :binary_id
      add :checked_in_at, :utc_datetime_usec
      add :checked_in_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :cancelled_at, :utc_datetime_usec
      add :late_cancel, :boolean, null: false, default: false
      add :removed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :trial_offered_at, :utc_datetime_usec
      add :converted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    composite_fk(:community_event_attendees, :event_id, :community_events)

    create constraint(:community_event_attendees, :community_event_attendees_status_check,
             check: "status IN ('going', 'waitlisted', 'cancelled')"
           )

    create constraint(:community_event_attendees, :community_event_attendees_source_check,
             check:
               "source IN ('member', 'open', 'guest') AND (source = 'guest') = (invited_by_id IS NOT NULL)"
           )

    create constraint(:community_event_attendees, :community_event_attendees_payment_check,
             check:
               "(paid_at IS NULL) = (payment_method IS NULL) AND " <>
                 "(payment_method IS NULL OR payment_method IN ('cash', 'bank_transfer', 'card_manual', 'other')) AND " <>
                 "(amount_cents IS NULL OR amount_cents >= 0)"
           )

    create constraint(:community_event_attendees, :community_event_attendees_cancel_check,
             check:
               "(status = 'cancelled') = (cancelled_at IS NOT NULL) AND (NOT late_cancel OR status = 'cancelled')"
           )

    create unique_index(:community_event_attendees, [:event_id, :user_id])
    create index(:community_event_attendees, [:event_id, :status, :queued_at])
    create index(:community_event_attendees, [:user_id, :status])

    create index(:community_event_attendees, [:event_id, :invited_by_id],
             where: "invited_by_id IS NOT NULL"
           )

    create index(:community_event_attendees, [:organization_id, :user_id])

    for table <- ~w(community_events community_event_attendees), do: secure(table)

    me = "NULLIF(current_setting('app.user_id', true), '')::uuid"

    # The events a person has a row on, at any box (guests, open events).
    execute("""
    CREATE OR REPLACE FUNCTION palee_acting_user_event_ids()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT a.event_id FROM public.community_event_attendees a
      WHERE a.user_id = #{me}
    $$
    """)

    # From a personal session: the events of gyms you belong to, of open clubs
    # you are in, events open to everyone, and events you have a row on.
    execute("""
    CREATE POLICY community_events_member_read_policy ON community_events
    FOR SELECT
    USING (palee_acting_user_belongs_to(organization_id))
    """)

    execute("""
    CREATE POLICY community_events_open_club_read_policy ON community_events
    FOR SELECT
    USING (club_id IN (SELECT palee_acting_user_club_ids()))
    """)

    execute("""
    CREATE POLICY community_events_open_read_policy ON community_events
    FOR SELECT
    USING (#{me} IS NOT NULL AND open_to_non_members)
    """)

    execute("""
    CREATE POLICY community_events_attendee_read_policy ON community_events
    FOR SELECT
    USING (id IN (SELECT palee_acting_user_event_ids()))
    """)

    execute("""
    CREATE POLICY community_event_attendees_own_read_policy ON community_event_attendees
    FOR SELECT
    USING (user_id = #{me})
    """)

    # An event's card in the club feed is a post with an event attachment.
    replace_attachment_check(@attachments_before ++ ["event"])

    alter table(:scheduling_trial_requests) do
      add :referral_event_id, :binary_id
    end

    create index(:scheduling_trial_requests, [:referral_event_id],
             where: "referral_event_id IS NOT NULL"
           )

    replace_notification_types(@before_types ++ @event_types)
  end

  def down do
    replace_notification_types(@before_types)

    drop index(:scheduling_trial_requests, [:referral_event_id])

    alter table(:scheduling_trial_requests) do
      remove :referral_event_id
    end

    execute("DELETE FROM community_posts WHERE attachment_type = 'event'")
    replace_attachment_check(@attachments_before)

    drop table(:community_event_attendees)
    drop table(:community_events)
    execute("DROP FUNCTION IF EXISTS palee_acting_user_event_ids()")
  end

  defp replace_attachment_check(types) do
    execute("ALTER TABLE community_posts DROP CONSTRAINT community_posts_attachment_check")

    create constraint(:community_posts, :community_posts_attachment_check,
             check:
               "(attachment_type IS NULL AND attachment_id IS NULL AND attachment IS NULL) OR " <>
                 "(attachment_type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")}) AND attachment_id IS NOT NULL AND attachment IS NOT NULL)"
           )
  end

  defp composite_fk(table, column, parent) do
    execute("""
    ALTER TABLE #{table}
    ADD CONSTRAINT #{table}_#{column}_fkey
    FOREIGN KEY (#{column}, organization_id)
    REFERENCES #{parent} (id, organization_id) ON DELETE CASCADE
    """)
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end

  defp secure(table) do
    execute("""
    CREATE TRIGGER #{table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY #{table}_tenant_policy ON #{table}
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end
end
