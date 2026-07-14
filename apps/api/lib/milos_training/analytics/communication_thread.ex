defmodule MilosTraining.Analytics.CommunicationThread do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "communication_threads" do
    field :context_type, :string
    field :context_id, :binary_id
    field :status, :string, default: "open"
    field :created_by_id, :binary_id
    field :assigned_admin_id, :binary_id
    field :last_message_at, :utc_datetime_usec
    field :needs_follow_up_at, :utc_datetime_usec
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(thread \\ %__MODULE__{}, params) do
    thread
    |> cast(params, [
      :context_type,
      :context_id,
      :status,
      :created_by_id,
      :assigned_admin_id,
      :last_message_at,
      :needs_follow_up_at,
      :params
    ])
    |> validate_required([:context_type, :status, :created_by_id])
    |> validate_inclusion(:status, ["open", "resolved", "needs_follow_up"])
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:assigned_admin_id)
  end
end
