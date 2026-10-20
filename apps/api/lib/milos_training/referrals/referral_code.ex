defmodule MilosTraining.Referrals.ReferralCode do
  @moduledoc """
  A member's personal invite code at one box (ADR-156). The link and the QR
  are `/r/<code>`; the code alone finds the box. Revoked codes stop working
  but stay, so invites made with them keep their history.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "referral_codes" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :code, :string
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :user_id, :code])
    |> validate_required([:organization_id, :user_id, :code])
    |> unique_constraint(:code)
    |> unique_constraint([:organization_id, :user_id], name: :referral_codes_one_active_index)
  end

  def revoke_changeset(code, at), do: change(code, revoked_at: at)
end
