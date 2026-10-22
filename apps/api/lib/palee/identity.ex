defmodule Palee.Identity do
  alias Palee.Identity.Commands.{RegisterUser, UpdateRole}
  alias Palee.Identity.Domain.Locale
  alias Palee.Identity.Queries.FindUser
  alias Palee.Identity.UserStore

  defdelegate register(params), to: RegisterUser, as: :call
  defdelegate find_by_nickname(nickname), to: FindUser, as: :by_nickname
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
  ADR-177: the clock a person's own days follow (streaks, progress, "today"
  in their logs): the zone their device last reported, else the default.
  """
  def time_zone(%{time_zone: zone}), do: Palee.TimeZones.ZonedTime.or_default(zone)
  def time_zone(_account), do: Palee.TimeZones.ZonedTime.default_zone()

  @doc "ADR-177: the person's local date now."
  def local_today(user_id, now \\ DateTime.utc_now())

  def local_today(user_id, now) when is_binary(user_id),
    do: Palee.TimeZones.ZonedTime.local_date(now, time_zone(find_by_id(user_id)))

  def local_today(_user_id, now), do: Palee.TimeZones.ZonedTime.local_date(now, time_zone(nil))
  defdelegate mark_tour_completed(user_id, audience), to: UserStore
  defdelegate search_users(query), to: UserStore
  defdelegate count_by_role(role), to: UserStore
  defdelegate bump_security_version(user_id), to: UserStore
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
