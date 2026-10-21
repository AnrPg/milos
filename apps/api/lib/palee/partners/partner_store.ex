defmodule Palee.Partners.PartnerStore do
  @moduledoc """
  Facade over the configured Partners adapter (ADR-169). Every call runs
  inside a `RepoContext` session: the club's gym and the acting person.
  """

  @behaviour Palee.Partners.Ports.PartnerStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :partner_store)

  defp scoped(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def get_profile(context, club_id, user_id),
    do: scoped(context, :get_profile, [club_id, user_id])

  @impl true
  def get_profile_by_id(context, id), do: scoped(context, :get_profile_by_id, [id])

  @impl true
  def list_profiles_of(context, user_id), do: scoped(context, :list_profiles_of, [user_id])

  @impl true
  def profile_ids_for(context, pairs), do: scoped(context, :profile_ids_for, [pairs])

  @impl true
  def list_live_profiles(context, club_id, user_ids),
    do: scoped(context, :list_live_profiles, [club_id, user_ids])

  @impl true
  def create_profile(context, attrs), do: scoped(context, :create_profile, [attrs])

  @impl true
  def update_profile(context, profile, changes),
    do: scoped(context, :update_profile, [profile, changes])

  @impl true
  def set_active_for_user(context, user_id, active),
    do: scoped(context, :set_active_for_user, [user_id, active])

  @impl true
  def list_swipes_by(context, club_id, swiper_id),
    do: scoped(context, :list_swipes_by, [club_id, swiper_id])

  @impl true
  def count_swipes_since(context, swiper_id, since),
    do: scoped(context, :count_swipes_since, [swiper_id, since])

  @impl true
  def record_swipe(context, attrs, mutual?, now),
    do: scoped(context, :record_swipe, [attrs, mutual?, now])

  @impl true
  def delete_swipe(context, club_id, swiper_id, target_id),
    do: scoped(context, :delete_swipe, [club_id, swiper_id, target_id])

  @impl true
  def get_match(context, id), do: scoped(context, :get_match, [id])

  @impl true
  def list_matches(context, user_id), do: scoped(context, :list_matches, [user_id])

  @impl true
  def active_match_between(context, a, b), do: scoped(context, :active_match_between, [a, b])

  @impl true
  def active_partner_ids(context, user_id), do: scoped(context, :active_partner_ids, [user_id])

  @impl true
  def update_match(context, match, changes), do: scoped(context, :update_match, [match, changes])

  @impl true
  def end_matches(context, filter, changes), do: scoped(context, :end_matches, [filter, changes])

  @impl true
  def list_messages(context, match_id, cursor, limit),
    do: scoped(context, :list_messages, [match_id, cursor, limit])

  @impl true
  def insert_message(context, attrs, now), do: scoped(context, :insert_message, [attrs, now])

  @impl true
  def unread_counts(context, user_id, matches),
    do: scoped(context, :unread_counts, [user_id, matches])
end
