defmodule Palee.Execution.ExecutionPlanSet do
  @moduledoc """
  ADR-270: one set / round of a structured plan row as the athlete did it,
  prescribed next to actual (`Palee.Execution.Domain.PlanActuals`).
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fields ~w(execution_id user_id organization_id master_workout_id section_id row_id
             exercise_name exercise_ref block_index round_index part_index phase_index interrupt
             prescribed_reps_text prescribed_load_text prescribed_reps prescribed_load_kg
             prescribed_load_pct one_rep_max_kg actual_reps actual_load_kg logged)a

  schema "execution_plan_sets" do
    field :execution_id, :binary_id
    field :user_id, :binary_id
    field :organization_id, :binary_id
    field :master_workout_id, :binary_id
    field :section_id, :binary_id
    field :row_id, :string
    field :exercise_name, :string, default: ""
    field :exercise_ref, :string
    field :block_index, :integer
    field :round_index, :integer
    field :part_index, :integer, default: 0
    field :phase_index, :integer, default: 0
    field :interrupt, :boolean, default: false
    field :prescribed_reps_text, :string, default: ""
    field :prescribed_load_text, :string, default: ""
    field :prescribed_reps, :decimal
    field :prescribed_load_kg, :decimal
    field :prescribed_load_pct, :decimal
    field :one_rep_max_kg, :decimal
    field :actual_reps, :decimal
    field :actual_load_kg, :decimal
    field :logged, :boolean, default: false

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def fields, do: @fields

  @doc "The record as the API shows it (no owner columns)."
  def to_map(%__MODULE__{} = set) do
    Map.take(set, @fields -- ~w(execution_id user_id organization_id master_workout_id)a)
  end
end
