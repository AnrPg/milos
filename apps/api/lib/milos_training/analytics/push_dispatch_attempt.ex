defmodule MilosTraining.Analytics.PushDispatchAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "push_dispatch_attempts" do
    field :notification_id, :binary_id
    field :user_id, :binary_id
    field :endpoint_hash, :string
    field :status, :string, default: "pending"
    field :attempted_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :error, :string
    field :metadata, :map, default: %{}
  end

  def changeset(attempt \\ %__MODULE__{}, params) do
    attempt
    |> cast(params, [
      :notification_id,
      :user_id,
      :endpoint_hash,
      :status,
      :attempted_at,
      :completed_at,
      :error,
      :metadata
    ])
    |> validate_required([:user_id, :endpoint_hash, :status, :attempted_at])
    |> validate_inclusion(:status, ["pending", "sent", "failed", "expired"])
    |> foreign_key_constraint(:notification_id)
    |> foreign_key_constraint(:user_id)
  end
end
