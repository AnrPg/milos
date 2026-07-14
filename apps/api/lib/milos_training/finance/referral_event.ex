defmodule MilosTraining.Finance.ReferralEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "referral_events" do
    field :referral_program_id, :binary_id
    field :referrer_user_id, :binary_id
    field :referred_user_id, :binary_id
    field :membership_id, :binary_id
    field :status, :string, default: "pending"
    field :signup_source_snapshot, :string, default: "referral"
    field :notes, :string
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> cast(params, [
      :referral_program_id,
      :referrer_user_id,
      :referred_user_id,
      :membership_id,
      :status,
      :signup_source_snapshot,
      :notes,
      :params
    ])
    |> validate_required([:referrer_user_id, :referred_user_id, :status, :signup_source_snapshot])
    |> validate_inclusion(:status, ["pending", "approved", "applied", "rejected"])
    |> foreign_key_constraint(:referral_program_id)
    |> foreign_key_constraint(:referrer_user_id)
    |> foreign_key_constraint(:referred_user_id)
    |> foreign_key_constraint(:membership_id)
  end
end
