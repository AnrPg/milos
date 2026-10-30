defmodule Palee.Partners.PartnerStore do
  @moduledoc """
  Facade over the configured Partners adapter (ADR-169, ADR-280). Every call
  runs inside a personal `RepoContext` session: the acting person
  (`app.user_id`) and no gym, whatever else the caller's context holds.
  """

  @behaviour Palee.Partners.Ports.PartnerStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :partner_store)

  defp scoped(context, function, args) do
    personal = personal(context)
    RepoContext.run(personal, fn -> apply(adapter(), function, [personal | args]) end)
  end

  @doc "The personal session of a context: its acting person only."
  def personal(%{user_id: user_id}) when is_binary(user_id), do: %{user_id: user_id}
  def personal(_context), do: %{}

  @impl true
  def get_profile(context, user_id), do: scoped(context, :get_profile, [user_id])

  @impl true
  def get_profiles(_context, []), do: []
  def get_profiles(context, user_ids), do: scoped(context, :get_profiles, [user_ids])

  @impl true
  def list_live_profiles(context, excluded_ids),
    do: scoped(context, :list_live_profiles, [excluded_ids])

  @impl true
  def create_profile(context, attrs), do: scoped(context, :create_profile, [attrs])

  @impl true
  def update_profile(context, profile, changes),
    do: scoped(context, :update_profile, [profile, changes])

  @impl true
  def list_swipes_by(context, swiper_id), do: scoped(context, :list_swipes_by, [swiper_id])

  @impl true
  def count_swipes_since(context, swiper_id, since),
    do: scoped(context, :count_swipes_since, [swiper_id, since])

  @impl true
  def record_swipe(context, attrs, mutual?, now),
    do: scoped(context, :record_swipe, [attrs, mutual?, now])

  @impl true
  def delete_swipe(context, swiper_id, target_id),
    do: scoped(context, :delete_swipe, [swiper_id, target_id])

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

  @impl true
  def insert_report(context, attrs), do: scoped(context, :insert_report, [attrs])

  @impl true
  def get_report(context, id), do: scoped(context, :get_report, [id])

  @impl true
  def list_reports(context, status), do: scoped(context, :list_reports, [status])

  @impl true
  def decide_reports(context, target_id, changes),
    do: scoped(context, :decide_reports, [target_id, changes])
end
