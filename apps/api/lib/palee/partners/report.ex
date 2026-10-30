defmodule Palee.Partners.Report do
  @moduledoc """
  A person reported in Partners (ADR-280): who reported whom, why, an
  optional note, and the Palee team's decision. The reporter reads their
  own; vendors read and decide.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Partners.Domain.ReportPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_reports" do
    field :reporter_id, :binary_id
    field :target_id, :binary_id
    field :reason, :string
    field :note, :string
    field :status, :string, default: "open"
    field :decided_by_id, :binary_id
    field :decided_at, :utc_datetime_usec
    field :decision_note, :string

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:reporter_id, :target_id, :reason, :note])
    |> validate_required([:reporter_id, :target_id, :reason])
    |> validate_inclusion(:reason, ReportPolicy.reasons())
    |> validate_length(:note, max: ReportPolicy.note_max())
    |> check_constraint(:target_id, name: :partner_reports_pair_check)
    |> unique_constraint([:reporter_id, :target_id], name: :partner_reports_open_pair_index)
  end

  def decision_changeset(report, attrs) do
    report
    |> cast(attrs, [:status, :decided_by_id, :decided_at, :decision_note])
    |> validate_inclusion(:status, ReportPolicy.statuses())
    |> validate_length(:decision_note, max: ReportPolicy.note_max())
  end
end
