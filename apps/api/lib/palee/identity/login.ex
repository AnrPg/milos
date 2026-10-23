defmodule Palee.Identity.Login do
  @moduledoc """
  ADR-187: the credentials one person signs in with: one email (unique,
  case-insensitive), one password, shared by up to three profiles. Bumping
  `security_version` revokes the sessions of every profile at once.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Identity.RegistrationPolicy
  alias Palee.Organizations.Domain.InvitationEmail

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "logins" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :security_version, :integer, default: 0
    field :email_verified_at, :utc_datetime_usec
    field :last_used_user_id, :binary_id

    has_many :profiles, Palee.Identity.User

    timestamps()
  end

  def create_changeset(login \\ %__MODULE__{}, params) do
    login
    |> cast(params, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_email()
    |> validate_password()
  end

  @doc "A new email and/or password. A new password revokes every session."
  def credentials_changeset(login, params) do
    login
    |> cast(params, [:email, :password])
    |> then(fn changeset ->
      if get_change(changeset, :email), do: validate_email(changeset), else: changeset
    end)
    |> then(fn changeset ->
      if get_change(changeset, :password), do: validate_password(changeset), else: changeset
    end)
  end

  def last_used_changeset(login, user_id), do: change(login, last_used_user_id: user_id)

  def bump_security_changeset(login),
    do: change(login, security_version: (login.security_version || 0) + 1)

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &InvitationEmail.normalize/1)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "must be a valid email address"
    )
    |> unique_constraint(:email, name: :logins_email_unique_index)
  end

  defp validate_password(changeset) do
    validate_change(changeset, :password, fn :password, password ->
      if RegistrationPolicy.valid_password?(password),
        do: [],
        else: [password: "must be at least 4 characters"]
    end)
  end
end
