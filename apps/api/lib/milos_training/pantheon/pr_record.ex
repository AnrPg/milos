defmodule MilosTraining.Pantheon.PRRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_units ~w(mins_secs reps sets kcals m kg)

  schema "user_pr_records" do
    field :user_id, :binary_id
    field :name, :string
    field :current_score, :decimal
    field :unit, :string
    field :higher_is_better, :boolean, default: true
    field :beaten_on, :date

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record \\ %__MODULE__{}, params) do
    record
    |> cast(params, [:user_id, :name, :current_score, :unit, :higher_is_better, :beaten_on])
    |> validate_required([:user_id, :name, :current_score, :unit, :beaten_on])
    |> validate_inclusion(:unit, @valid_units)
    |> validate_number(:current_score, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end

  def valid_units, do: @valid_units
end
