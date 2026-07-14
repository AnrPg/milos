defmodule MilosTraining.Execution.WorkoutExecution do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @sources [:class_booking, :assigned, :self_selected]
  @statuses [:active, :paused, :completed]

  schema "workout_executions" do
    field(:user_id, :binary_id)
    field(:master_workout_id, :binary_id)
    field(:scale_level_slug, :string)
    field(:source, Ecto.Enum, values: @sources, default: :self_selected)
    field(:source_reference_id, :binary_id)
    field(:status, Ecto.Enum, values: @statuses, default: :active)
    field(:started_at_utc, :utc_datetime_usec)
    field(:started_at_tz, :string, default: "UTC")
    field(:completed_at_utc, :utc_datetime_usec)
    field(:completed_at_tz, :string)
    field(:current_segment_index, :integer, default: 0)
    field(:segment_started_at_utc, :utc_datetime_usec)
    field(:paused_elapsed_ms, :integer, default: 0)
    field(:resume_countdown_ends_at_utc, :utc_datetime_usec)
    field(:total_elapsed_ms, :integer, default: 0)
    field(:section_elapsed_ms, :map, default: %{})
    field(:segment_cycle_counts, :map, default: %{})
    field(:checked_exercise_ids, {:array, :string}, default: [])
    field(:section_scores, {:array, :map}, default: [])
    field(:exercise_notes, {:array, :map}, default: [])
    field(:exercise_modifications, {:array, :map}, default: [])

    timestamps(updated_at: false)
  end

  def start_changeset(execution \\ %__MODULE__{}, params) do
    execution
    |> cast(params, [
      :user_id,
      :master_workout_id,
      :scale_level_slug,
      :source,
      :source_reference_id,
      :status,
      :started_at_utc,
      :started_at_tz,
      :current_segment_index,
      :segment_started_at_utc,
      :paused_elapsed_ms,
      :resume_countdown_ends_at_utc,
      :total_elapsed_ms,
      :section_elapsed_ms,
      :segment_cycle_counts
    ])
    |> validate_required([:user_id, :started_at_utc, :source, :status])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:current_segment_index, greater_than_or_equal_to: 0)
    |> validate_number(:paused_elapsed_ms, greater_than_or_equal_to: 0)
    |> validate_number(:total_elapsed_ms, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:master_workout_id)
  end

  def complete_changeset(execution, params) do
    execution
    |> cast(params, [
      :completed_at_utc,
      :completed_at_tz,
      :status,
      :current_segment_index,
      :segment_started_at_utc,
      :paused_elapsed_ms,
      :resume_countdown_ends_at_utc,
      :total_elapsed_ms,
      :section_elapsed_ms,
      :segment_cycle_counts,
      :checked_exercise_ids,
      :section_scores,
      :exercise_notes
    ])
    |> validate_required([:completed_at_utc])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:current_segment_index, greater_than_or_equal_to: 0)
    |> validate_number(:paused_elapsed_ms, greater_than_or_equal_to: 0)
    |> validate_number(:total_elapsed_ms, greater_than_or_equal_to: 0)
  end

  def progress_changeset(execution, params) do
    execution
    |> cast(params, [
      :status,
      :current_segment_index,
      :segment_started_at_utc,
      :paused_elapsed_ms,
      :resume_countdown_ends_at_utc,
      :total_elapsed_ms,
      :section_elapsed_ms,
      :segment_cycle_counts,
      :checked_exercise_ids,
      :section_scores,
      :exercise_notes,
      :exercise_modifications
    ])
    |> validate_required([:status, :current_segment_index, :paused_elapsed_ms])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:current_segment_index, greater_than_or_equal_to: 0)
    |> validate_number(:paused_elapsed_ms, greater_than_or_equal_to: 0)
    |> validate_number(:total_elapsed_ms, greater_than_or_equal_to: 0)
  end
end
