defmodule MilosTraining.Finance.ReferralProgram do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "referral_programs" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :reward_type, :string, default: "manual"
    field :reward_value, :integer, default: 0
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(program \\ %__MODULE__{}, params) do
    program
    |> cast(params, [:name, :description, :active, :reward_type, :reward_value, :params])
    |> validate_required([:name, :reward_type])
    |> validate_inclusion(:reward_type, ["credit", "discount", "free_period", "manual"])
    |> validate_number(:reward_value, greater_than_or_equal_to: 0)
  end
end
