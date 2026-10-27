defmodule Palee.Organizations.RegistrationInvitation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary
  alias Palee.Organizations.Domain.{InvitationPolicy, MembershipPolicy}

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
    # A coach's client invitation: the redeemed client becomes theirs (ADR-100).
    field :coach_user_id, :binary_id
    # ADR-186: the role set (`role` is its primary role; empty = `[role]`) and
    # the branches the redeemed membership works at.
    field :roles, {:array, Ecto.Enum}, values: MembershipPolicy.roles(), default: []
    field :all_locations, :boolean, default: true
    field :location_ids, {:array, :binary_id}, default: []
    # ADR-209: the invited address (encrypted) for resends and the pending
    # list, the email's language, when the token went only into an email, and
    # whether a bound invitation needs a verified address or the emailed link.
    field :intended_email_encrypted, EncryptedBinary, redact: true
    field :email_locale, :string
    field :emailed_at, :utc_datetime_usec
    field :email_verification_required, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def issue_changeset(invitation \\ %__MODULE__{}, params, issued_at) do
    invitation
    |> cast(params, [
      :organization_id,
      :token_digest,
      :role,
      :expires_at,
      :issued_by_user_id,
      :intended_email_digest,
      :coach_user_id,
      :roles,
      :all_locations,
      :location_ids,
      :intended_email_encrypted,
      :email_locale,
      :emailed_at,
      :email_verification_required
    ])
    |> validate_required([:organization_id, :token_digest, :role, :expires_at])
    |> validate_digest(:token_digest)
    |> validate_optional_digest(:intended_email_digest)
    |> validate_expiry(issued_at)
    |> check_constraint(:location_ids,
      name: :registration_invitations_location_scope_check,
      message: "must list between 1 and 200 locations"
    )
    |> unique_constraint(:token_digest)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:issued_by_user_id)
  end

  @doc "ADR-186: the role set an invitation grants (older links carry one role)."
  def granted_roles(%__MODULE__{roles: [_ | _] = roles}), do: roles
  def granted_roles(%__MODULE__{role: role}), do: [role]

  @doc "ADR-186: the branch scope an invitation grants, `:all` or location ids."
  def granted_scope(%__MODULE__{all_locations: false, location_ids: [_ | _] = ids}), do: ids
  def granted_scope(%__MODULE__{}), do: :all

  def redeem_changeset(invitation, user_id, redeemed_at) do
    invitation
    |> cast(%{redeemed_by_user_id: user_id, redeemed_at: redeemed_at}, [
      :redeemed_by_user_id,
      :redeemed_at
    ])
    |> validate_required([:redeemed_by_user_id, :redeemed_at])
    |> foreign_key_constraint(:redeemed_by_user_id)
    |> check_constraint(:redeemed_at,
      name: :registration_invitations_terminal_state_check
    )
  end

  def revoke_changeset(invitation, revoked_at) do
    invitation
    |> cast(%{revoked_at: revoked_at}, [:revoked_at])
    |> validate_required([:revoked_at])
    |> check_constraint(:revoked_at,
      name: :registration_invitations_terminal_state_check
    )
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
