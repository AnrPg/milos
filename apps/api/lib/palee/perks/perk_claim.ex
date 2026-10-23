defmodule Palee.Perks.PerkClaim do
  @moduledoc """
  A member's claim of a perk (ADR-191): it reveals the code (the shared
  code, a pool code, or the short code under the QR) and is used once.
  `token_hash` is the SHA-256 of the QR's secret nonce
  (`Domain.VerificationToken`); it is never shown or exported.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "perk_claims" do
    field :organization_id, :binary_id, read_after_writes: true
    field :perk_id, :binary_id
    field :perk_version, :integer
    field :user_id, :binary_id
    field :code, :string
    field :token_hash, :string, redact: true
    field :status, :string, default: "claimed"
    field :claimed_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    field :used_via, :string
    field :used_by_id, :binary_id
    field :revoked_at, :utc_datetime_usec
    field :revoked_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :organization_id,
      :perk_id,
      :perk_version,
      :user_id,
      :code,
      :token_hash,
      :claimed_at
    ])
    |> validate_required([:organization_id, :perk_id, :perk_version, :user_id, :code, :claimed_at])
    |> check_constraint(:status, name: :perk_claims_status_check)
    |> foreign_key_constraint(:perk_id, name: :perk_claims_perk_id_fkey)
  end

  def revoke_changeset(%__MODULE__{} = claim, actor_id, at),
    do: change(claim, status: "revoked", revoked_at: at, revoked_by_id: actor_id)
end
