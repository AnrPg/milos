defmodule Palee.Identity do
  alias Palee.Identity.Commands.{RegisterUser, UpdateRole}
  alias Palee.Identity.Domain.{Locale, SignInDevice}
  alias Palee.Identity.Queries.FindUser
  alias Palee.Identity.UserStore

  defdelegate register(params), to: RegisterUser, as: :call

  # ADR-184: mock people of a demo business, marked durably on the profile.
  @doc """
  Registers a mock person of the demo business `organization_id`. The mark
  (`demo_organization_id`) is set at insert and never changes.
  """
  defdelegate register_demo_person(organization_id, params),
    to: UserStore,
    as: :create_demo_person

  @doc "Whether an account (or account id) is a mock person of some demo business."
  def demo_user?(%{demo_organization_id: organization_id}), do: not is_nil(organization_id)

  def demo_user?(user_id) when is_binary(user_id),
    do: user_id |> find_by_id() |> demo_user?()

  def demo_user?(_user), do: false

  @doc "The mock people of one demo business (the wipe and cleanup delete these)."
  defdelegate demo_user_ids(organization_id), to: UserStore

  @doc """
  The ids among `user_ids` that `viewer_id` may discover, in their order. A
  mock person is visible only to itself and to the active staff of its demo
  business; everyone real is always kept. Every person-discovery path filters
  through this (or the SQL `palee_demo_user_visible`).
  """
  defdelegate visible_user_ids(user_ids, viewer_id), to: UserStore

  @doc "Whether `viewer_id` may discover the person `user_id` (see `visible_user_ids/2`)."
  def visible_to?(user_id, viewer_id) when is_binary(user_id),
    do: visible_user_ids([user_id], viewer_id) == [user_id]

  def visible_to?(_user_id, _viewer_id), do: false

  @doc """
  ADR-193 §4: what people search matches for typed text: the handle form
  (by prefix) and the folded display-name form (anywhere in the name).
  """
  def people_search_terms(query) when is_binary(query) do
    {Palee.Identity.Domain.Handle.normalize(query) || "",
     Palee.Identity.Domain.NameSearch.fold(query)}
  end

  defdelegate find_by_nickname(nickname), to: FindUser, as: :by_nickname
  defdelegate find_by_handle(handle), to: FindUser, as: :by_nickname

  # ADR-187: logins (one per email) and their up to three profiles.
  defdelegate create_login_with_profile(params), to: UserStore
  defdelegate add_profile(login_id, params), to: UserStore
  defdelegate find_login_by_email(email), to: UserStore, as: :get_login_by_email
  defdelegate find_by_email(email), to: UserStore, as: :get_by_email
  defdelegate list_profiles(login_id), to: UserStore
  defdelegate touch_last_used(login_id, user_id), to: UserStore
  defdelegate handle_available?(handle, except_user_id \\ nil), to: UserStore
  defdelegate update_credentials(user_id, params), to: UserStore
  defdelegate reset_login_password(login_id, password), to: UserStore

  @doc """
  Records that the login can read `email` (an emailed link to it was
  opened). Only marks the login's current address; `{:error, :email_mismatch}`
  when the login's email changed since the link was sent.
  """
  def mark_email_verified(login_id, email, now \\ DateTime.utc_now()),
    do: UserStore.mark_email_verified(login_id, email, now)

  @doc "Whether the account's login has proved it reads its email."
  def email_verified?(%{email_verified_at: %DateTime{}}), do: true
  def email_verified?(_account), do: false
  defdelegate max_profiles(), to: Palee.Identity.Domain.ProfilePolicy
  defdelegate find_by_id(id), to: FindUser, as: :by_id
  defdelegate list_by_ids(ids), to: FindUser, as: :list_by_ids
  defdelegate list_by_role(role), to: FindUser, as: :list_by_role
  defdelegate list_all_users(), to: FindUser, as: :list_all
  defdelegate search_athletes(query), to: FindUser, as: :search_athletes
  defdelegate delete(user), to: UserStore, as: :delete_user
  defdelegate delete_tenant_scoped_user(user), to: UserStore
  defdelegate update_role(user, role), to: UpdateRole, as: :call
  defdelegate regenerate_calendar_feed_token(user), to: UserStore
  defdelegate update_profile(user_id, params), to: UserStore
  defdelegate update_avatar(user_id, avatar_url), to: UserStore
  defdelegate update_time_zone(user_id, time_zone), to: UserStore

  @doc """
  ADR-179: the clock a person's own days follow (streaks, progress, "today"
  in their logs): the zone their device last reported, else the default.
  """
  def time_zone(%{time_zone: zone}), do: Palee.TimeZones.ZonedTime.or_default(zone)
  def time_zone(_account), do: Palee.TimeZones.ZonedTime.default_zone()

  @doc "ADR-179: the person's local date now."
  def local_today(user_id, now \\ DateTime.utc_now())

  def local_today(user_id, now) when is_binary(user_id),
    do: Palee.TimeZones.ZonedTime.local_date(now, time_zone(find_by_id(user_id)))

  def local_today(_user_id, now), do: Palee.TimeZones.ZonedTime.local_date(now, time_zone(nil))
  defdelegate mark_tour_completed(user_id, audience), to: UserStore
  defdelegate tour_audiences, to: Palee.Identity.Domain.ProductTours, as: :audiences
  defdelegate search_users(query), to: UserStore
  defdelegate count_by_role(role), to: UserStore
  defdelegate bump_security_version(user_id), to: UserStore
  defdelegate bump_login_security_version(login_id), to: UserStore

  @doc """
  ADR-208: remembers the device a login signs in (`:sign_in`) or signs up
  (`:sign_up`) from. Returns `{outcome, description}`: `:new` only when the
  login has signed in before and never from this device.
  """
  def remember_sign_in_device(login_id, device_id, user_agent, source, now \\ DateTime.utc_now()) do
    description = SignInDevice.describe(user_agent)
    hash = SignInDevice.hash(device_id, description)

    {Palee.Identity.LoginDeviceStore.remember(login_id, hash, description, source, now),
     description}
  end

  defdelegate valid_device_id?(id), to: SignInDevice, as: :valid_id?
  defdelegate generate_device_id(), to: SignInDevice, as: :generate_id
  defdelegate supported_locales(), to: Locale, as: :supported

  # Remembered filters of list surfaces (ADR-151).
  alias Palee.Identity.Domain.FilterPolicy
  alias Palee.Identity.SavedFilterStore
  defdelegate filter_surfaces(), to: FilterPolicy, as: :surfaces
  defdelegate max_named_filters(), to: FilterPolicy, as: :max_named
  defdelegate validate_filter_surface(surface), to: FilterPolicy, as: :validate_surface
  defdelegate validate_filter_params(params), to: FilterPolicy, as: :validate_params
  defdelegate normalize_filter_name(name), to: FilterPolicy, as: :normalize_name
  defdelegate list_saved_filters(context, surface), to: SavedFilterStore, as: :list

  defdelegate put_last_used_filter(context, surface, params, at),
    to: SavedFilterStore,
    as: :put_last_used

  defdelegate put_named_filter(context, surface, name, params, at),
    to: SavedFilterStore,
    as: :put_named

  defdelegate count_named_filters(context, surface), to: SavedFilterStore, as: :count_named
  defdelegate delete_named_filter(context, id), to: SavedFilterStore, as: :delete_named

  # ADR-154: daily alerts of named Γύρω μου filters.
  defdelegate set_filter_alert(context, id, enabled, now), to: SavedFilterStore, as: :set_alert
  defdelegate filter_alert_candidates(day, limit), to: SavedFilterStore, as: :alert_candidates
  defdelegate claim_filter_alert(context, id, day), to: SavedFilterStore, as: :claim_alert
  defdelegate finish_filter_alert(context, id, at), to: SavedFilterStore, as: :finish_alert

  @doc "Secret-free account records for a tenant export (ADR-117)."
  def export_accounts(user_ids) when is_list(user_ids) do
    user_ids
    |> list_by_ids()
    |> Enum.map(&Palee.Identity.Domain.AccountExport.to_export/1)
  end
end
