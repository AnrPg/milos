defmodule Palee.Community.EventStore do
  @moduledoc """
  Facade over the configured events adapter (ADR-153). Every call runs
  inside a `RepoContext` session: the gym's scope for its events, a
  person's own session for the places they hold at any box.
  """

  @behaviour Palee.Community.Ports.EventStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :community_event_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def insert_events(context, attrs), do: call(context, :insert_events, [attrs])
  @impl true
  def get_event(context, id), do: call(context, :get_event, [id])
  @impl true
  def list_events(context, filter), do: call(context, :list_events, [filter])
  @impl true
  def update_event(context, event, attrs), do: call(context, :update_event, [event, attrs])

  @impl true
  def set_event_lifecycle(context, event, attrs),
    do: call(context, :set_event_lifecycle, [event, attrs])

  @impl true
  def claim_event(context, id, field, now), do: call(context, :claim_event, [id, field, now])
  @impl true
  def reminders_due(context, window), do: call(context, :reminders_due, [window])
  @impl true
  def with_event_lock(context, id, fun), do: call(context, :with_event_lock, [id, fun])

  @impl true
  def get_attendee(context, event_id, user_id),
    do: call(context, :get_attendee, [event_id, user_id])

  @impl true
  def list_attendees(context, event_ids, statuses),
    do: call(context, :list_attendees, [event_ids, statuses])

  @impl true
  def attendee_counts(context, event_ids), do: call(context, :attendee_counts, [event_ids])

  @impl true
  def count_guests(context, event_id, inviter_id),
    do: call(context, :count_guests, [event_id, inviter_id])

  @impl true
  def insert_attendee(context, attrs), do: call(context, :insert_attendee, [attrs])

  @impl true
  def update_attendee(context, attendee, attrs),
    do: call(context, :update_attendee, [attendee, attrs])

  @impl true
  def attendances_of(context, user_id, statuses),
    do: call(context, :attendances_of, [user_id, statuses])

  @impl true
  def late_cancel_counts(context, user_ids, since),
    do: call(context, :late_cancel_counts, [user_ids, since])

  @impl true
  def mark_converted(context, user_id, window, at),
    do: call(context, :mark_converted, [user_id, window, at])

  # ADR-185 ------------------------------------------------------------------

  @impl true
  def creation_counts(context, since, now), do: call(context, :creation_counts, [since, now])

  @impl true
  def list_cohosts(context, event_ids), do: call(context, :list_cohosts, [event_ids])
  @impl true
  def get_cohost(context, id), do: call(context, :get_cohost, [id])
  @impl true
  def insert_cohost(context, attrs), do: call(context, :insert_cohost, [attrs])

  @impl true
  def update_cohost(context, cohost, attrs),
    do: call(context, :update_cohost, [cohost, attrs])

  @impl true
  def cohost_requests(context, organization_id),
    do: call(context, :cohost_requests, [organization_id])

  @impl true
  def respond_cohost(context, id, status, now),
    do: call(context, :respond_cohost, [id, status, now])

  @impl true
  def accepted_cohosts(context, event_ids, cohost_ids),
    do: call(context, :accepted_cohosts, [event_ids, cohost_ids])

  @impl true
  def cohosted_by?(context, event_id, organization_id),
    do: call(context, :cohosted_by?, [event_id, organization_id])

  @impl true
  def cohost_trial_offer_facts(context, id), do: call(context, :cohost_trial_offer_facts, [id])

  @impl true
  def claim_cohost_trial_offer(context, id, now),
    do: call(context, :claim_cohost_trial_offer, [id, now])

  @impl true
  def record_view(context, event_id, day, viewer_key),
    do: call(context, :record_view, [event_id, day, viewer_key])

  @impl true
  def view_totals(context, event_ids), do: call(context, :view_totals, [event_ids])

  # A system sweep (ADR-131 §2): the definer answers ids only, outside any scope.
  @impl true
  def empty_organiser_organization_ids(context, before),
    do: adapter().empty_organiser_organization_ids(context, before)
end
