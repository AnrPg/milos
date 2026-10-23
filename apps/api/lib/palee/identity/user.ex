defmodule Palee.Identity.User do
  @moduledoc """
  A profile (ADR-187). Every foreign key in the schema points at profiles;
  the credentials they share live on `Palee.Identity.Login`.

  The `handle` and `display_name` fields map to the historical `nickname`
  and `display_nickname` columns, which SQL functions and views reference.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Palee.Identity.{Domain.Locale, Login, RegistrationPolicy}
  alias Palee.Identity.Domain.{DisplayName, Handle, NameSearch}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :handle, :string, source: :nickname
    field :display_name, :string, source: :display_nickname
    field :search_text, :string, default: ""
    field :handle_changed_at, :utc_datetime_usec
    field :role, Ecto.Enum, values: RegistrationPolicy.roles()
    field :calendar_feed_token_version, :integer, default: 1
    field :security_version, :integer, default: 1
    field :avatar_url, :string
    field :preferred_locale, :string, default: "en"
    # "frost" (light) or "graphite" (dark); nil is the default, frost.
    field :preferred_theme_slug, :string
    field :completed_tours, {:array, :string}, default: []
    # ADR-179: the zone the person's device last reported; nil until it does.
    field :time_zone, :string

    belongs_to :login, Login

    timestamps()
  end

  @doc """
  A new profile under `login_id`. `handle` is what the person typed (folded
  here); `display_name` defaults to the typed handle so a profile always has
  a name to show.
  """
  def profile_create_changeset(user \\ %__MODULE__{}, login_id, params) do
    params = default_display_name(params)

    user
    |> cast(params, [:handle, :display_name, :role])
    |> put_change(:login_id, login_id)
    |> validate_required([:handle, :display_name, :role])
    |> validate_inclusion(:role, RegistrationPolicy.self_register_roles())
    |> validate_handle()
    |> validate_display_name()
    |> put_search_text()
    |> unique_constraint(:handle, name: :users_nickname_index, message: "has already been taken")
    |> check_constraint(:login_id,
      name: :users_profile_cap,
      message: "has reached the profile limit"
    )
  end

  def role_changeset(user, params) do
    user
    |> cast(params, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, RegistrationPolicy.roles())
  end

  @doc "Profile-level settings. Credentials (email, password) change on the login."
  def profile_changeset(user, params, now \\ DateTime.utc_now()) do
    user
    |> cast(params, [:handle, :display_name, :preferred_locale, :preferred_theme_slug])
    |> maybe_change_handle(now)
    |> validate_display_name()
    |> put_search_text()
    |> validate_inclusion(:preferred_locale, Locale.supported(), message: "is not supported")
    |> validate_inclusion(:preferred_theme_slug, Palee.Themes.slugs(),
      message: "is not supported"
    )
    |> unique_constraint(:handle, name: :users_nickname_index, message: "has already been taken")
  end

  def tours_changeset(user, completed_tours) do
    user
    |> cast(%{completed_tours: completed_tours}, [:completed_tours])
    |> validate_subset(:completed_tours, Palee.Identity.Domain.ProductTours.audiences())
  end

  @doc "ADR-179: the zone the person's device reports (an IANA name)."
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

  defp default_display_name(params) do
    handle = value(params, :handle) || value(params, :nickname)
    display = value(params, :display_name)

    params
    |> Map.new(fn {key, val} -> {to_string(key), val} end)
    |> Map.put("handle", handle)
    |> Map.put("display_name", if(blank?(display), do: handle, else: display))
  end

  defp maybe_change_handle(changeset, now) do
    case get_change(changeset, :handle) do
      nil ->
        changeset

      _handle ->
        changeset
        |> validate_handle()
        |> then(fn changeset ->
          if get_change(changeset, :handle),
            do: put_change(changeset, :handle_changed_at, now),
            else: changeset
        end)
    end
  end

  defp validate_handle(changeset) do
    case get_change(changeset, :handle) do
      typed when is_binary(typed) ->
        if Handle.valid?(typed) do
          normalized = Handle.normalize(typed)

          if normalized == changeset.data.handle,
            do: delete_change(changeset, :handle),
            else: put_change(changeset, :handle, normalized)
        else
          add_error(
            changeset,
            :handle,
            "must be 3-30 Latin letters, numbers, dots or underscores"
          )
        end

      _other ->
        changeset
    end
  end

  defp validate_display_name(changeset) do
    case get_change(changeset, :display_name) do
      typed when is_binary(typed) ->
        if DisplayName.valid?(typed),
          do: put_change(changeset, :display_name, DisplayName.normalize(typed)),
          else: add_error(changeset, :display_name, "must be 1-50 characters")

      _other ->
        changeset
    end
  end

  defp put_search_text(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp put_search_text(changeset) do
    if changed?(changeset, :handle) or changed?(changeset, :display_name) do
      put_change(
        changeset,
        :search_text,
        NameSearch.key(get_field(changeset, :display_name), get_field(changeset, :handle))
      )
    else
      changeset
    end
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
