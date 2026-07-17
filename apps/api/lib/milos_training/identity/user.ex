defmodule MilosTraining.Identity.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias MilosTraining.Identity.{Domain.Locale, RegistrationPolicy}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :nickname, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :display_nickname, :string
    field :role, Ecto.Enum, values: RegistrationPolicy.roles()
    field :calendar_feed_token_version, :integer, default: 1
    field :security_version, :integer, default: 1
    field :avatar_url, :string
    field :preferred_locale, :string, default: "en"

    timestamps()
  end

  def registration_changeset(user \\ %__MODULE__{}, params) do
    user
    |> cast(params, [:nickname, :password, :role])
    |> validate_required([:nickname, :password, :role])
    |> validate_nickname()
    |> normalize_and_preserve_nickname()
    |> validate_inclusion(:role, RegistrationPolicy.self_register_roles())
    |> validate_password()
    |> unique_constraint(:nickname)
  end

  def admin_registration_changeset(user \\ %__MODULE__{}, params) do
    user
    |> cast(params, [:nickname, :password, :role])
    |> validate_required([:nickname, :password, :role])
    |> validate_nickname()
    |> normalize_and_preserve_nickname()
    |> validate_inclusion(:role, [:admin])
    |> validate_password()
    |> unique_constraint(:nickname)
  end

  defp maybe_normalize_nickname(changeset) do
    case Ecto.Changeset.get_change(changeset, :nickname) do
      nil ->
        changeset

      _v ->
        changeset
        |> validate_nickname()
        |> normalize_and_preserve_nickname()
    end
  end

  defp maybe_validate_nickname(changeset) do
    case Ecto.Changeset.get_change(changeset, :nickname) do
      nil ->
        changeset

      _v ->
        changeset
        |> validate_nickname()
        |> unique_constraint(:nickname)
    end
  end

  defp maybe_validate_password(changeset) do
    case Ecto.Changeset.get_change(changeset, :password) do
      nil -> changeset
      _v -> validate_password(changeset)
    end
  end

  def role_changeset(user, params) do
    user
    |> cast(params, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, RegistrationPolicy.roles())
  end

  def profile_changeset(user, params) do
    user
    |> cast(params, [:nickname, :password, :preferred_locale])
    |> maybe_normalize_nickname()
    |> maybe_validate_nickname()
    |> maybe_validate_password()
    |> validate_inclusion(:preferred_locale, Locale.supported(), message: "is not supported")
  end

  def avatar_changeset(user, params) do
    user
    |> cast(params, [:avatar_url])
  end

  def calendar_feed_token_changeset(user, params) do
    user
    |> cast(params, [:calendar_feed_token_version])
    |> validate_required([:calendar_feed_token_version])
    |> validate_number(:calendar_feed_token_version, greater_than: 0)
  end

  def security_version_changeset(user, version) do
    user
    |> change(security_version: version)
    |> validate_number(:security_version, greater_than: 0)
  end

  defp validate_nickname(changeset) do
    validate_change(changeset, :nickname, fn :nickname, nickname ->
      if RegistrationPolicy.valid_nickname?(nickname),
        do: [],
        else: [nickname: "must be 3-30 letters, numbers, or underscores"]
    end)
  end

  defp normalize_and_preserve_nickname(changeset) do
    case Ecto.Changeset.get_change(changeset, :nickname) do
      nickname when is_binary(nickname) ->
        changeset
        |> put_change(:display_nickname, nickname)
        |> put_change(:nickname, RegistrationPolicy.normalize_nickname(nickname))

      _ ->
        changeset
    end
  end

  defp validate_password(changeset) do
    validate_change(changeset, :password, fn :password, password ->
      if RegistrationPolicy.valid_password?(password),
        do: [],
        else: [password: "must be at least 4 characters and contain no whitespace"]
    end)
  end
end
