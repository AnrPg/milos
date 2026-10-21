defmodule Palee.Nutrition.Plan do
  @moduledoc "A client's current nutrition plan, written by staff (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Nutrition.Domain.PortionPolicy

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
    field :portion_targets, :map
    field :meal_slots, {:array, :string}, default: []
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
    :portion_targets,
    :meal_slots,
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
    |> validate_portions()
    |> validate_subset(:meal_slots, PortionPolicy.slots())
    |> update_change(:meal_slots, &Enum.uniq/1)
    |> check_constraint(:meal_slots, name: :nutrition_plans_meal_slots_check)
    |> unique_constraint([:organization_id, :user_id])
  end

  defp validate_portions(changeset) do
    case PortionPolicy.validate(get_change(changeset, :portion_targets)) do
      {:ok, targets} -> put_change(changeset, :portion_targets, targets)
      {:error, message} -> add_error(changeset, :portion_targets, message)
    end
  end
end
