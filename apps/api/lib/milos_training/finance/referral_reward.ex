defmodule MilosTraining.Finance.ReferralReward do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "referral_rewards" do
    field :referral_event_id, :binary_id
    field :recipient_user_id, :binary_id
    field :membership_id, :binary_id
    field :reward_type, :string
    field :reward_value, :integer, default: 0
    field :status, :string, default: "pending"
    field :applied_at, :utc_datetime_usec
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reward \\ %__MODULE__{}, params) do
    reward
    |> cast(params, [
      :referral_event_id,
      :recipient_user_id,
      :membership_id,
      :reward_type,
      :reward_value,
      :status,
      :applied_at,
      :params
    ])
    |> validate_required([
      :referral_event_id,
      :recipient_user_id,
      :reward_type,
      :reward_value,
      :status
    ])
    |> validate_inclusion(:reward_type, ["credit", "discount", "free_period", "manual"])
    |> validate_inclusion(:status, ["pending", "approved", "applied", "rejected"])
    |> validate_number(:reward_value, greater_than_or_equal_to: 0)
    |> unique_constraint(:referral_event_id)
    |> foreign_key_constraint(:referral_event_id)
    |> foreign_key_constraint(:recipient_user_id)
    |> foreign_key_constraint(:membership_id)
  end
end
