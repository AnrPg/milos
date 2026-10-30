defmodule Palee.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @types [
    :booking_approved,
    :booking_rejected,
    :booking_pending,
    :booking_timeout,
    :workout_note,
    :workout_changed,
    :workout_deleted,
    :workout_rejected,
    :workout_moved,
    :workout_assigned,
    :workout_assignment_requested,
    :review_submitted,
    :athlete_message,
    :workout_completed,
    :coaching_message,
    :box_message,
    :challenge_completed,
    :chat_message,
    :invoice_issued,
    :payment_reminder,
    :booking_waitlist_promoted,
    :package_expiring,
    :form_review_submitted,
    :form_review_completed,
    :coaching_reply_overdue,
    :nutrition_plan_updated,
    :training_goal_updated,
    :appointment_booked,
    :appointment_cancelled,
    :class_cancelled,
    :coach_client_assigned,
    :inventory_repair_needed,
    :inventory_stock_low,
    :inventory_digest,
    :shop_stock_low,
    :shop_order_placed,
    :payment_failed,
    :payment_needs_attention,
    :fiscal_connection_failed,
    :shop_order_ready,
    :shop_order_reminder,
    :shop_order_cancelled,
    :shop_back_in_stock,
    :coach_note_viewed,
    :subscription_expiring,
    :subscription_grace,
    :access_ended,
    :follow_requested,
    :follow_accepted,
    :new_follower,
    :person_message,
    :message_request,
    :trial_requested,
    :trial_booked,
    :trial_cancelled,
    :trial_accepted,
    :trial_declined,
    :trial_reminder,
    :trial_follow_up,
    :trial_class_cancelled,
    :community_group_proposed,
    :community_group_approved,
    :community_group_declined,
    :community_group_join_requested,
    :community_group_join_approved,
    :community_group_archive_warning,
    :community_report_created,
    :community_club_join_requested,
    :community_club_join_approved,
    :community_squad_invited,
    :community_event_waitlist_promoted,
    :community_event_cancelled,
    :community_event_changed,
    :community_event_reminder,
    :community_event_guest_joined,
    :community_event_trial_offer,
    :community_event_message,
    :community_event_cohost_request,
    :community_event_cohost_answered,
    :referral_progress,
    :referral_reward,
    :referral_review,
    :around_new_matches,
    :check_in_visitor,
    :body_measure_reminder,
    :buddy_invite,
    :buddy_accepted,
    :support_request,
    :support_reply,
    :support_no_reply_nudge,
    :buddy_weekly_summary,
    :buddy_message,
    :partner_match,
    :partner_message,
    :coach_wellness_summary,
    :craving_follow_up,
    :water_reminder,
    :journal_export_ready,
    :device_sync_error,
    :season_requested,
    :season_confirmed,
    :season_declined,
    :season_cancelled,
    :class_workout_missing,
    :password_reset_requested,
    :password_reset_completed,
    :business_demo_idle,
    :email_key_expiring,
    :member_leaving,
    # ADR-252: documents to sign and health certificates.
    :document_signature_requested,
    :health_certificate_expiring,
    # ADR-280 verification: sponsors and the Palee check of Partners.
    :partner_vouch_request,
    :partner_vouched,
    :partner_verification_decided,
    :partner_sponsor_penalty
  ]

  schema "notifications" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :type, Ecto.Enum, values: @types
    field :payload, :map, default: %{}
    field :dedupe_key, :string
    field :read_at, :utc_datetime

    timestamps(updated_at: false)
  end

  @doc "Every notification type, as atoms (ADR-199 maps each to a category)."
  def types, do: @types

  def changeset(notification \\ %__MODULE__{}, params) do
    notification
    |> cast(params, [:organization_id, :user_id, :type, :payload, :dedupe_key, :read_at])
    |> validate_required([:user_id, :type])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:dedupe_key, name: :notifications_user_id_dedupe_key_index)
  end
end
