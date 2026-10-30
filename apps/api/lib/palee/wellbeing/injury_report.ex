defmodule Palee.Wellbeing.InjuryReport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "injury_reports" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :reported_by_id, :binary_id
    field :reported_by_role, :string
    field :body_area, :string
    field :severity, :string, default: "mild"
    field :status, :string, default: "active"
    field :started_on, :date
    field :healed_on, :date
    field :description, :string
    field :training_limitations, :string
    field :tags, {:array, :string}, default: []
    field :visibility, :string, default: "user_and_admin"
    # ADR-286: a member's own report reaches their boxes' staff while on.
    field :shared_with_box, :boolean, default: true
    field :params, :map, default: %{}
    # ADR-139 ladder rung; coaches always see injuries, so it is never private.
    field :journal_visibility, :string, default: "coach_can_view"

    has_many :events, Palee.Wellbeing.InjuryStatusEvent, foreign_key: :injury_report_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Moves the injury_report on the journal ladder (ADR-139)."
  def visibility_changeset(%__MODULE__{} = injury_report, rung) do
    injury_report
    |> change(journal_visibility: rung)
    |> check_constraint(:journal_visibility, name: :injury_reports_journal_visibility_check)
  end

  @doc "The member shares the report with their boxes, or stops (ADR-286)."
  def box_sharing_changeset(%__MODULE__{} = injury_report, shared?) when is_boolean(shared?),
    do: change(injury_report, shared_with_box: shared?)

  def changeset(injury_report \\ %__MODULE__{}, params) do
    injury_report
    |> cast(params, [
      :organization_id,
      :user_id,
      :reported_by_id,
      :reported_by_role,
      :body_area,
      :severity,
      :status,
      :started_on,
      :healed_on,
      :description,
      :training_limitations,
      :tags,
      :visibility,
      :shared_with_box,
      :params
    ])
    |> validate_required([
      :user_id,
      :reported_by_id,
      :reported_by_role,
      :body_area,
      :severity,
      :status
    ])
    |> validate_inclusion(:reported_by_role, ["self", "admin"])
    |> validate_inclusion(:severity, ["mild", "moderate", "severe"])
    |> validate_inclusion(:status, ["active", "healed"])
    |> validate_inclusion(:visibility, ["admin_only", "user_and_admin"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:reported_by_id)
  end
end
