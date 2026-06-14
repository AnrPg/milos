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
    :athlete_message,
    :workout_completed,
    :admin_note,
    :challenge_completed,
    :chat_message
  ]

  schema "notifications" do
    field :user_id, :binary_id
    field :type, Ecto.Enum, values: @types
    field :payload, :map, default: %{}
    field :dedupe_key, :string
    field :read_at, :utc_datetime

    timestamps(updated_at: false)
  end

  def changeset(notification \\ %__MODULE__{}, params) do
    notification
    |> cast(params, [:user_id, :type, :payload, :dedupe_key, :read_at])
    |> validate_required([:user_id, :type])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:dedupe_key, name: :notifications_user_id_dedupe_key_index)
  end
end
