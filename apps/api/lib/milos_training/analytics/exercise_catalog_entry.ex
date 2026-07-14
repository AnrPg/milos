defmodule MilosTraining.Analytics.ExerciseCatalogEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exercise_catalog_entries" do
    field :name, :string
    field :normalized_name, :string
    field :movement_pattern, :string
    field :equipment, {:array, :string}, default: []
    field :muscle_groups, {:array, :string}, default: []
    field :skill_domain, :string
    field :progression_level, :string
    field :tags, {:array, :string}, default: []
    field :params, :map, default: %{}
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry \\ %__MODULE__{}, params) do
    entry
    |> cast(params, [
      :name,
      :normalized_name,
      :movement_pattern,
      :equipment,
      :muscle_groups,
      :skill_domain,
      :progression_level,
      :tags,
      :params,
      :active
    ])
    |> put_normalized_name()
    |> validate_required([:name, :normalized_name, :active])
    |> unique_constraint(:normalized_name)
  end

  defp put_normalized_name(changeset) do
    case get_field(changeset, :normalized_name) || get_field(changeset, :name) do
      nil ->
        changeset

      name ->
        put_change(changeset, :normalized_name, normalize_name(name))
    end
  end

  defp normalize_name(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end
end
