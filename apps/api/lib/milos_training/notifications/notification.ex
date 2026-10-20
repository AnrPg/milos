defmodule MilosTraining.Notifications.Notification do
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
    :appointment_booked,
    :appointment_cancelled,
    :coach_client_assigned,
    :inventory_repair_needed,
    :inventory_stock_low,
    :inventory_digest,
    :coach_note_viewed,
    :subscription_expiring,
    :subscription_grace,
    :access_ended,
    :follow_requested,
    :follow_accepted,
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
    :community_club_join_approved
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

  def changeset(notification \\ %__MODULE__{}, params) do
    notification
    |> cast(params, [:organization_id, :user_id, :type, :payload, :dedupe_key, :read_at])
    |> validate_required([:user_id, :type])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:dedupe_key, name: :notifications_user_id_dedupe_key_index)
  end
end
