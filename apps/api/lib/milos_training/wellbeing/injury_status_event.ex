defmodule MilosTraining.Wellbeing.InjuryStatusEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "injury_status_events" do
    field :injury_report_id, :binary_id
    field :actor_id, :binary_id
    field :event_type, :string
    field :payload, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
  end

  def changeset(injury_status_event \\ %__MODULE__{}, params) do
    injury_status_event
    |> cast(params, [:injury_report_id, :actor_id, :event_type, :payload, :occurred_at])
    |> validate_required([:injury_report_id, :actor_id, :event_type, :occurred_at])
    |> validate_inclusion(:event_type, [
      "reported",
      "updated",
      "marked_healed",
      "reopened",
      "note_added"
    ])
    |> foreign_key_constraint(:injury_report_id)
    |> foreign_key_constraint(:actor_id)
  end
end
