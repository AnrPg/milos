defmodule MilosTraining.Scaling.ScalingSuggestion do
  @moduledoc """
  One advisor answer for one athlete's assignment and the coach's decision
  on it (ADR-174). Only an approved row carries `modifications` (ADR-050
  patches) and only an approved row reaches the member.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved dismissed no_change superseded)

  schema "scaling_suggestions" do
    field :organization_id, :binary_id
    field :athlete_id, :binary_id
    field :assigned_workout_id, :binary_id
    field :master_workout_id, :binary_id
    field :scheduled_for, :date
    field :status, :string, default: "pending"
    field :summary, :string
    field :scale_level_slug, :string
    field :items, {:array, :map}, default: []
    field :modifications, {:array, :map}, default: []
    field :injury_regions, {:array, :string}, default: []
    field :input_digest, :string
    field :provider, :string
    field :model, :string
    field :operation_id, :binary_id
    field :coach_note, :string
    field :reviewed_by_id, :binary_id
    field :reviewed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @create_fields [
    :athlete_id,
    :assigned_workout_id,
    :master_workout_id,
    :scheduled_for,
    :status,
    :summary,
    :scale_level_slug,
    :items,
    :injury_regions,
    :input_digest,
    :provider,
    :model,
    :operation_id
  ]

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @create_fields)
    |> validate_required([
      :athlete_id,
      :assigned_workout_id,
      :master_workout_id,
      :scheduled_for,
      :status,
      :input_digest
    ])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :scaling_suggestions_values_check)
    |> unique_constraint([:assigned_workout_id, :athlete_id],
      name: :scaling_suggestions_live_index
    )
  end

  def update_changeset(suggestion, changes) do
    suggestion
    |> cast(changes, [
      :status,
      :items,
      :scale_level_slug,
      :modifications,
      :coach_note,
      :reviewed_by_id,
      :reviewed_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :scaling_suggestions_values_check)
  end
end
