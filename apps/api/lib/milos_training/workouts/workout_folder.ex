defmodule MilosTraining.Workouts.WorkoutFolder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workout_folders" do
    field :organization_id, :binary_id
    field :name, :string
    field :parent_id, :binary_id
    field :created_by_id, :binary_id

    timestamps()
  end

  def changeset(folder \\ %__MODULE__{}, params) do
    folder
    |> cast(params, [:name, :parent_id, :created_by_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :created_by_id])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_change(:parent_id, fn :parent_id, parent_id ->
      if parent_id == folder.id, do: [parent_id: "cannot be the folder itself"], else: []
    end)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint(:name, name: :workout_folders_parent_name_index)
    |> unique_constraint(:name, name: :workout_folders_root_name_index)
  end
end
