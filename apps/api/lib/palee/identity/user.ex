defmodule Palee.Identity.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias Palee.Identity.{Domain.Locale, RegistrationPolicy}
  alias Palee.Organizations.Domain.InvitationEmail

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
    # "frost" (light) or "graphite" (dark); nil is the default, frost.
    field :preferred_theme_slug, :string
    # Nullable: every account created before F-10 predates this column.
    field :email, :string
    field :completed_tours, {:array, :string}, default: []
    # ADR-177: the zone the person's device last reported; nil until it does.
    field :time_zone, :string

    timestamps()
  end

  def registration_changeset(user \\ %__MODULE__{}, params) do
    user
    |> cast(params, [:nickname, :password, :role, :email])
    |> validate_required([:nickname, :password, :role, :email])
    |> maybe_validate_email()
    |> validate_nickname()
    |> normalize_and_preserve_nickname()
    |> validate_inclusion(:role, RegistrationPolicy.self_register_roles())
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
    |> cast(params, [:nickname, :password, :preferred_locale, :preferred_theme_slug, :email])
    |> maybe_validate_email()
    |> maybe_normalize_nickname()
    |> maybe_validate_nickname()
    |> maybe_validate_password()
    |> validate_inclusion(:preferred_locale, Locale.supported(), message: "is not supported")
    |> validate_inclusion(:preferred_theme_slug, Palee.Themes.slugs(),
      message: "is not supported"
    )
  end

  def tours_changeset(user, completed_tours) do
    user
    |> cast(%{completed_tours: completed_tours}, [:completed_tours])
    |> validate_subset(:completed_tours, Palee.Identity.Domain.ProductTours.audiences())
  end

  @doc "ADR-177: the zone the person's device reports (an IANA name)."
  def time_zone_changeset(user, time_zone) do
    user
    |> cast(%{time_zone: time_zone}, [:time_zone])
    |> validate_required([:time_zone])
    |> validate_change(:time_zone, fn :time_zone, zone ->
      if Palee.TimeZones.ZonedTime.valid?(zone),
        do: [],
        else: [time_zone: "is not a known time zone"]
    end)
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

  # Applied only when the caller actually supplied an address, so accounts
  # without one keep working and an unrelated profile edit never has to
  # invent a value.
  defp maybe_validate_email(changeset) do
    case get_change(changeset, :email) do
      nil ->
        changeset

      _email ->
        changeset
        |> update_change(:email, &InvitationEmail.normalize/1)
        |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
          message: "must be a valid email address"
        )
        |> unique_constraint(:email, name: :users_email_unique_index)
    end
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
        else: [password: "must be at least 4 characters"]
    end)
  end
end
