defmodule MilosTraining.Buddies.BuddyStore do
  @moduledoc """
  Facade over the configured Buddies adapter (ADR-160). Every call on a
  person's rows runs inside a `RepoContext` session, theirs.
  """

  @behaviour MilosTraining.Buddies.Ports.BuddyStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :buddy_store)

  defp scoped(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list_links(context, user_id, ended_since),
    do: scoped(context, :list_links, [user_id, ended_since])

  @impl true
  def get_link(context, id), do: scoped(context, :get_link, [id])

  @impl true
  def create_link(context, attrs, guard), do: scoped(context, :create_link, [attrs, guard])

  @impl true
  def update_link(context, link, changes), do: scoped(context, :update_link, [link, changes])

  @impl true
  def expire_stale(context, user_id, now), do: scoped(context, :expire_stale, [user_id, now])

  @impl true
  def active_links_as_requester(context, user_id),
    do: scoped(context, :active_links_as_requester, [user_id])

  @impl true
  def open_links_between(context, a, b), do: scoped(context, :open_links_between, [a, b])

  @impl true
  def relation(context, other_id), do: scoped(context, :relation, [other_id])

  @impl true
  def candidates(context, term, limit), do: scoped(context, :candidates, [term, limit])

  # The public landing page: a definer lookup answering one link's preview.
  @impl true
  def invite_preview(token_hash, now), do: adapter().invite_preview(token_hash, now)

  @impl true
  def claim_invite(context, token_hash, now),
    do: scoped(context, :claim_invite, [token_hash, now])

  @impl true
  def quiet_hours(context, buddy_id), do: scoped(context, :quiet_hours, [buddy_id])

  @impl true
  def shared_phone(context, requester_id), do: scoped(context, :shared_phone, [requester_id])

  # A definer lookup across people: ids and zones only, no session needed.
  @impl true
  def summary_requesters(limit), do: adapter().summary_requesters(limit)

  @impl true
  def get_settings(context, user_id), do: scoped(context, :get_settings, [user_id])

  @impl true
  def put_settings(context, user_id, changes),
    do: scoped(context, :put_settings, [user_id, changes])

  @impl true
  def create_request(context, attrs, deliveries, guard, window_start),
    do: scoped(context, :create_request, [attrs, deliveries, guard, window_start])

  @impl true
  def count_requests_between(context, user_id, from, to),
    do: scoped(context, :count_requests_between, [user_id, from, to])

  @impl true
  def get_request(context, id), do: scoped(context, :get_request, [id])

  @impl true
  def list_requests(context, user_id, role, limit),
    do: scoped(context, :list_requests, [user_id, role, limit])

  @impl true
  def list_deliveries(context, request_ids), do: scoped(context, :list_deliveries, [request_ids])

  @impl true
  def list_replies(context, request_ids), do: scoped(context, :list_replies, [request_ids])

  @impl true
  def undo_request(context, id, now), do: scoped(context, :undo_request, [id, now])

  @impl true
  def mark_delivered(context, id, now), do: scoped(context, :mark_delivered, [id, now])

  @impl true
  def mark_nudged(context, id, now), do: scoped(context, :mark_nudged, [id, now])

  @impl true
  def insert_reply(context, attrs, now), do: scoped(context, :insert_reply, [attrs, now])

  @impl true
  def list_summary_grants(context, user_id),
    do: scoped(context, :list_summary_grants, [user_id])

  @impl true
  def grant_summary(context, user_id, scope, now),
    do: scoped(context, :grant_summary, [user_id, scope, now])

  @impl true
  def withdraw_summary(context, user_id, scope, now),
    do: scoped(context, :withdraw_summary, [user_id, scope, now])
end
