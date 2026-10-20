defmodule MilosTraining.Wallet.WalletPass do
  @moduledoc """
  A member's Wallet card at one box (ADR-155): Apple or Google, with the
  serial its barcode is signed with. Revoking it stops it scanning at once.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @platforms ~w(apple google)

  schema "wallet_passes" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :platform, :string
    field :serial, :string
    field :auth_token_hash, :binary, redact: true
    field :revoked_at, :utc_datetime_usec
    field :last_updated_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def platforms, do: @platforms

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :user_id,
      :platform,
      :serial,
      :auth_token_hash,
      :last_updated_at
    ])
    |> validate_required([
      :organization_id,
      :user_id,
      :platform,
      :serial,
      :auth_token_hash,
      :last_updated_at
    ])
    |> validate_inclusion(:platform, @platforms)
    |> unique_constraint(:serial)
    |> unique_constraint([:organization_id, :user_id, :platform],
      name: :wallet_passes_one_active_index
    )
  end
end
