defmodule Palee.BusinessAccounts.ActivationLink do
  @moduledoc """
  ADR-184: a vendor's one-time link that activates one demo business when the
  account it names opens it, giving that account the chosen role. Only the
  digest of the token is stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.BusinessAccounts.Domain.ActivationLinkPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "business_activation_links" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :role, :string
    field :token_digest, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :created_by_id, :binary_id
    # ADR-205: the verified address the link was issued for and emailed to.
    field :email, :string
    field :redeemed_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def issue_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :user_id,
      :role,
      :token_digest,
      :expires_at,
      :created_by_id,
      :email
    ])
    |> validate_required([:organization_id, :user_id, :role, :token_digest, :expires_at])
    |> validate_inclusion(:role, ActivationLinkPolicy.roles())
    |> unique_constraint(:organization_id, name: :business_activation_links_one_live_index)
    |> unique_constraint(:token_digest)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end

  def revoke_changeset(link, at), do: change(link, revoked_at: at)
end
