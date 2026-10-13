defmodule MilosTraining.Nutrition.Plan do
  @moduledoc "A client's current nutrition plan, written by staff (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "nutrition_plans" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :title, :string
    field :body, :string
    field :daily_calories, :integer
    field :protein_grams, :integer
    field :carbs_grams, :integer
    field :fat_grams, :integer
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :title,
    :body,
    :daily_calories,
    :protein_grams,
    :carbs_grams,
    :fat_grams,
    :updated_by_id
  ]

  def changeset(plan \\ %__MODULE__{}, params) do
    plan
    |> cast(params, [:organization_id, :user_id | @fields])
    |> validate_required([:organization_id, :user_id, :title, :body])
    |> validate_length(:title, min: 2, max: 120)
    |> validate_length(:body, min: 2, max: 20_000)
    |> validate_number(:daily_calories, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:protein_grams, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000)
    |> validate_number(:carbs_grams, greater_than_or_equal_to: 0, less_than_or_equal_to: 2000)
    |> validate_number(:fat_grams, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000)
    |> unique_constraint([:organization_id, :user_id])
  end
end
