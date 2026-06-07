defmodule MilosTraining.Workouts.WorkoutSection do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.Domain.TimerConfig
  alias MilosTraining.Workouts.{MasterWorkout, WorkoutExercise}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workout_sections" do
    field :name, :string
    field :order, :integer
    field :scoreable, :boolean, default: false
    field :score_config, :map
    field :timer_config, :map

    belongs_to :master_workout, MasterWorkout
    belongs_to :parent_section, __MODULE__
    has_many :exercises, WorkoutExercise, preload_order: [asc: :order]

    timestamps(updated_at: false)
  end

  def changeset(section \\ %__MODULE__{}, params) do
    section
    |> base_changeset(params)
    |> cast_assoc(:exercises, required: true, with: &WorkoutExercise.changeset/2)
  end

  def persist_changeset(section \\ %__MODULE__{}, params) do
    section
    |> base_changeset(params)
  end

  defp base_changeset(section, params) do
    section
    |> cast(params, [
      :master_workout_id,
      :name,
      :order,
      :scoreable,
      :score_config,
      :timer_config,
      :parent_section_id
    ])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name, :order])
    |> validate_number(:order, greater_than_or_equal_to: 1)
    |> normalize_timer_config()
    |> foreign_key_constraint(:master_workout_id)
    |> foreign_key_constraint(:parent_section_id,
      name: :workout_sections_parent_same_workout_fkey
    )
    |> unique_constraint(:order, name: :workout_sections_root_order_index)
    |> unique_constraint(:order, name: :workout_sections_child_order_index)
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name), do: String.trim(name)

  defp normalize_timer_config(changeset) do
    case fetch_change(changeset, :timer_config) do
      {:ok, timer_config} ->
        case TimerConfig.normalize(timer_config) do
          {:ok, normalized} -> put_change(changeset, :timer_config, normalized)
          {:error, reason} -> add_error(changeset, :timer_config, reason)
        end

      :error ->
        changeset
    end
  end
end
