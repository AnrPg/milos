defmodule Palee.Setup.RecipeApplication do
  @moduledoc "One applied setup recipe (ADR-255). Rows are never changed."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fields ~w(recipe_key recipe_version applied_by_id applied_at changes manual change_count)a

  schema "setup_recipe_applications" do
    field :organization_id, :binary_id, read_after_writes: true
    field :recipe_key, :string
    field :recipe_version, :integer
    field :applied_by_id, :binary_id
    field :applied_at, :utc_datetime_usec
    field :changes, {:array, :map}, default: []
    field :manual, {:array, :map}, default: []
    field :change_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(application \\ %__MODULE__{}, attrs) do
    application
    |> cast(attrs, @fields)
    |> validate_required([:recipe_key, :recipe_version, :applied_at, :change_count])
    |> validate_length(:recipe_key, max: 60)
    |> validate_number(:recipe_version, greater_than: 0)
    |> validate_number(:change_count, greater_than_or_equal_to: 0)
  end
end
