defmodule MilosTraining.Organizations.RegistrationInvitation do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.{InvitationPolicy, MembershipPolicy}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @sha256_bytes 32

  schema "registration_invitations" do
    field :organization_id, :binary_id
    field :token_digest, :binary
    field :role, Ecto.Enum, values: MembershipPolicy.roles()
    field :expires_at, :utc_datetime_usec
    field :redeemed_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :issued_by_user_id, :binary_id
    field :redeemed_by_user_id, :binary_id
    field :intended_email_digest, :binary

    timestamps(type: :utc_datetime_usec)
  end

  def issue_changeset(invitation \\ %__MODULE__{}, params, issued_at) do
    invitation
    |> cast(params, [
      :organization_id,
      :token_digest,
      :role,
      :expires_at,
      :issued_by_user_id,
      :intended_email_digest
    ])
    |> validate_required([:organization_id, :token_digest, :role, :expires_at])
    |> validate_digest(:token_digest)
    |> validate_optional_digest(:intended_email_digest)
    |> validate_expiry(issued_at)
    |> unique_constraint(:token_digest)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:issued_by_user_id)
  end

  defp validate_digest(changeset, field) do
    validate_change(changeset, field, fn ^field, digest ->
      if is_binary(digest) and byte_size(digest) == @sha256_bytes,
        do: [],
        else: [{field, "must be a SHA-256 digest"}]
    end)
  end

  defp validate_optional_digest(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      _digest -> validate_digest(changeset, field)
    end
  end

  defp validate_expiry(changeset, issued_at) do
    validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if InvitationPolicy.valid_expiry?(expires_at, issued_at),
        do: [],
        else: [expires_at: "must be between 5 minutes and 7 days after issuance"]
    end)
  end
end
