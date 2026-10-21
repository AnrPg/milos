defmodule MilosTraining.Referrals.ReferralAttribution do
  @moduledoc """
  One friend at one box, from the first invite to the first payment
  (ADR-156). First invite wins inside the programme's window; each funnel
  step is stamped once; when the invite qualifies it opens the Finance
  referral the admin approves (`finance_referral_event_id`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Referrals.Domain.Attribution

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "referral_attributions" do
    field :organization_id, :binary_id
    field :referrer_user_id, :binary_id
    field :referred_user_id, :binary_id
    field :code_id, :binary_id
    field :community_event_id, :binary_id
    field :channel, :string
    field :referral_program_id, :binary_id
    field :new_account, :boolean, default: false
    field :attributed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :event_at, :utc_datetime_usec
    field :trial_at, :utc_datetime_usec
    field :joined_at, :utc_datetime_usec
    field :paid_at, :utc_datetime_usec
    field :status, :string, default: "open"
    field :qualified_at, :utc_datetime_usec
    field :void_reason, :string
    field :finance_referral_event_id, :binary_id
    field :friend_gift_applied_at, :utc_datetime_usec
    field :friend_gift_applied_by_id, :binary_id
    field :previous_referrer_user_id, :binary_id
    field :reassigned_at, :utc_datetime_usec
    field :reassigned_by_id, :binary_id
    field :notes, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :referrer_user_id,
      :referred_user_id,
      :code_id,
      :community_event_id,
      :channel,
      :referral_program_id,
      :new_account,
      :attributed_at,
      :expires_at,
      :event_at,
      :notes
    ])
    |> validate_required([
      :organization_id,
      :referrer_user_id,
      :referred_user_id,
      :channel,
      :attributed_at,
      :expires_at
    ])
    |> validate_inclusion(:channel, Attribution.channels())
    |> validate_length(:notes, max: 500)
    |> check_constraint(:referrer_user_id, name: :referral_attributions_not_self_check)
    |> unique_constraint([:organization_id, :referred_user_id])
  end

  @doc "Funnel steps, status changes and staff edits; the domain decides what is allowed."
  def update_changeset(attribution, changes) do
    attribution
    |> cast(changes, [
      :referrer_user_id,
      :code_id,
      :community_event_id,
      :channel,
      :referral_program_id,
      :new_account,
      :attributed_at,
      :expires_at,
      :event_at,
      :trial_at,
      :joined_at,
      :paid_at,
      :status,
      :qualified_at,
      :void_reason,
      :finance_referral_event_id,
      :friend_gift_applied_at,
      :friend_gift_applied_by_id,
      :previous_referrer_user_id,
      :reassigned_at,
      :reassigned_by_id,
      :notes
    ])
    |> validate_inclusion(:status, Attribution.statuses())
    |> validate_inclusion(:channel, Attribution.channels())
    |> validate_length(:notes, max: 500)
    |> check_constraint(:referrer_user_id, name: :referral_attributions_not_self_check)
    |> unique_constraint(:finance_referral_event_id)
  end
end
