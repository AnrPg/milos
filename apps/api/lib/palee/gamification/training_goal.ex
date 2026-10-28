defmodule Palee.Gamification.TrainingGoal do
  @moduledoc "A person's training goal of one kind (ADR-226); see `Domain.WeeklyGoal`."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Gamification.Domain.WeeklyGoal

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "training_goals" do
    field :user_id, :binary_id
    field :kind, :string
    field :target, :integer
    field :set_by_id, :binary_id
    field :set_by_role, :string
    field :set_in_organization_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(goal \\ %__MODULE__{}, params) do
    goal
    |> cast(params, [:user_id, :kind, :target, :set_by_id, :set_by_role, :set_in_organization_id])
    |> validate_required([:user_id, :kind, :target, :set_by_role])
    |> validate_inclusion(:kind, [WeeklyGoal.kind()])
    |> validate_number(:target,
      greater_than_or_equal_to: WeeklyGoal.min_target(),
      less_than_or_equal_to: WeeklyGoal.max_target()
    )
    |> validate_inclusion(:set_by_role, WeeklyGoal.set_by_roles())
    |> unique_constraint([:user_id, :kind])
    |> check_constraint(:target, name: :training_goals_shape_check)
    |> foreign_key_constraint(:user_id)
  end
end
