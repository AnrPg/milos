defmodule MilosTraining.Finance.ReferralProgram do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "referral_programs" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :reward_type, :string, default: "manual"
    field :reward_value, :integer, default: 0
    field :params, :map, default: %{}
    # ADR-156: the friend's side and the programme's own rules.
    field :friend_reward_type, :string, default: "none"
    field :friend_reward_value, :integer, default: 0
    field :friend_reward_note, :string
    field :reward_note, :string
    field :qualifying_stage, :string, default: "paid"
    field :attribution_days, :integer, default: 30
    field :yearly_cap, :integer
    field :approval, :string, default: "manual"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(program \\ %__MODULE__{}, params) do
    program
    |> cast(params, [
      :name,
      :description,
      :active,
      :reward_type,
      :reward_value,
      :params,
      :friend_reward_type,
      :friend_reward_value,
      :friend_reward_note,
      :reward_note,
      :qualifying_stage,
      :attribution_days,
      :yearly_cap,
      :approval
    ])
    |> validate_required([:name, :reward_type])
    |> validate_inclusion(:reward_type, ["credit", "discount", "free_period", "manual"])
    |> validate_number(:reward_value, greater_than_or_equal_to: 0)
    |> validate_inclusion(:friend_reward_type, ["none", "free_days", "credit", "custom"])
    |> validate_number(:friend_reward_value, greater_than_or_equal_to: 0)
    |> validate_length(:friend_reward_note, max: 200)
    |> validate_length(:reward_note, max: 200)
    |> validate_inclusion(:qualifying_stage, ["trial", "paid"])
    |> validate_number(:attribution_days,
      greater_than_or_equal_to: 7,
      less_than_or_equal_to: 365
    )
    |> validate_number(:yearly_cap, greater_than_or_equal_to: 1, less_than_or_equal_to: 1000)
    |> validate_inclusion(:approval, ["manual", "auto"])
    |> unique_constraint(:active, name: :referral_programs_one_active_index)
  end
end
