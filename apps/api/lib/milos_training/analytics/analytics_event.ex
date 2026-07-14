defmodule MilosTraining.Analytics.AnalyticsEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "analytics_events" do
    field :event_name, :string
    field :user_id, :binary_id
    field :actor_role_snapshot, :string
    field :context_type, :string
    field :context_id, :binary_id
    field :occurred_at, :utc_datetime_usec
    field :metadata, :map, default: %{}
  end

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> cast(params, [
      :event_name,
      :user_id,
      :actor_role_snapshot,
      :context_type,
      :context_id,
      :occurred_at,
      :metadata
    ])
    |> validate_required([:event_name, :occurred_at])
    |> foreign_key_constraint(:user_id)
  end
end
