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
    field :role, Ecto.Enum, values: RegistrationPolicy.roles()
    field :calendar_feed_token_version, :integer, default: 1
    field :avatar_url, :string
    field :preferred_locale, :string, default: "en"

    timestamps()
  end

  def registration_changeset(user \\ %__MODULE__{}, params) do
    user
    |> cast(params, [:nickname, :password, :role])
    |> update_change(:nickname, &RegistrationPolicy.normalize_nickname/1)
    |> validate_required([:nickname, :password, :role])
    |> validate_length(:nickname, min: 3, max: 30)
    |> validate_format(:nickname, ~r/^[a-zA-Z0-9_]+$/)
    |> validate_inclusion(:role, RegistrationPolicy.self_register_roles())
    |> validate_length(:password, min: 8)
    |> unique_constraint(:nickname)
  end

  defp maybe_normalize_nickname(changeset) do
    case Ecto.Changeset.get_change(changeset, :nickname) do
      nil ->
        changeset

      _v ->
        Ecto.Changeset.update_change(
          changeset,
          :nickname,
          &RegistrationPolicy.normalize_nickname/1
        )
    end
  end

  defp maybe_validate_nickname(changeset) do
    case Ecto.Changeset.get_change(changeset, :nickname) do
      nil ->
        changeset

      _v ->
        changeset
        |> validate_length(:nickname, min: 3, max: 30)
        |> validate_format(:nickname, ~r/^[a-zA-Z0-9_]+$/)
        |> unique_constraint(:nickname)
    end
  end

  defp maybe_validate_password(changeset) do
    case Ecto.Changeset.get_change(changeset, :password) do
      nil -> changeset
      _v -> validate_length(changeset, :password, min: 8)
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
    |> cast(params, [:nickname, :password, :avatar_url, :preferred_locale])
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
end
