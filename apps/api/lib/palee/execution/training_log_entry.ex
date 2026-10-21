defmodule Palee.Execution.TrainingLogEntry do
  @moduledoc """
  Standalone training-log entry (ADR-118).

  Records a workout the user performed without a timer-backed
  `workout_executions` row: a class they attended, an assigned or library
  workout done offline, or a freeform session. Entries are never deleted;
  they are voided so history and projections stay auditable.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(class assigned_workout library_workout freeform)
  @statuses ~w(logged voided)

  schema "training_log_entries" do
    field(:organization_id, :binary_id)
    field(:user_id, :binary_id)
    field(:source_type, :string)
    field(:source_reference_id, :binary_id)
    field(:master_workout_id, :binary_id)
    field(:booking_id, :binary_id)
    field(:title, :string)
    field(:workout_type, :string)
    field(:scale_level_slug, :string)
    field(:performed_at_utc, :utc_datetime_usec)
    field(:performed_at_tz, :string, default: "UTC")
    field(:duration_seconds, :integer)
    field(:perceived_effort, :integer)
    field(:section_scores, {:array, :map}, default: [])
    field(:performed_exercises, {:array, :map}, default: [])
    field(:status, :string, default: "logged")
    field(:voided_at, :utc_datetime_usec)
    field(:void_reason, :string)
    field(:idempotency_key, :string)
    field(:lock_version, :integer, default: 1)
    # ADR-139 ladder rung, set when logged from the member's `workout` default.
    field(:journal_visibility, :string, default: "coach_can_view")

    timestamps(type: :utc_datetime_usec)
  end

  @editable_fields [
    :title,
    :performed_at_utc,
    :performed_at_tz,
    :duration_seconds,
    :perceived_effort,
    :section_scores,
    :performed_exercises,
    :scale_level_slug
  ]

  def source_types, do: @source_types

  def create_changeset(entry \\ %__MODULE__{}, params) do
    entry
    |> cast(
      params,
      [
        :organization_id,
        :user_id,
        :source_type,
        :source_reference_id,
        :master_workout_id,
        :booking_id,
        :workout_type,
        :idempotency_key,
        :journal_visibility
      ] ++ @editable_fields
    )
    |> validate_required([
      :organization_id,
      :user_id,
      :source_type,
      :title,
      :performed_at_utc,
      :idempotency_key
    ])
    |> validate_common()
    |> validate_inclusion(:source_type, @source_types)
    |> check_constraint(:source_reference_id,
      name: :training_log_entries_source_reference_check
    )
    |> unique_constraint(:idempotency_key, name: :training_log_entries_idempotency_index)
    |> unique_constraint(:source_reference_id,
      name: :training_log_entries_live_source_index,
      message: "has already been logged"
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:master_workout_id)
  end

  @doc "Moves the entry on the journal ladder (ADR-139)."
  def visibility_changeset(%__MODULE__{} = entry, rung) do
    entry
    |> change(journal_visibility: rung)
    |> check_constraint(:journal_visibility, name: :training_log_entries_journal_visibility_check)
  end

  def update_changeset(%__MODULE__{} = entry, params) do
    entry
    |> cast(params, @editable_fields)
    |> validate_required([:title, :performed_at_utc])
    |> validate_common()
    |> optimistic_lock(:lock_version)
  end

  def void_changeset(%__MODULE__{} = entry, params) do
    entry
    |> cast(params, [:status, :voided_at, :void_reason])
    |> validate_required([:status, :voided_at])
    |> validate_inclusion(:status, ["voided"])
    |> validate_length(:void_reason, max: 500)
    |> optimistic_lock(:lock_version)
  end

  defp validate_common(changeset) do
    changeset
    |> validate_length(:title, min: 1, max: 160)
    |> validate_number(:duration_seconds, greater_than_or_equal_to: 0)
    |> validate_number(:perceived_effort, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_inclusion(:status, @statuses)
  end
end
