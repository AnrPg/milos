defmodule MilosTraining.Community.EventStore do
  @moduledoc """
  Facade over the configured events adapter (ADR-153). Every call runs
  inside a `RepoContext` session: the gym's scope for its events, a
  person's own session for the places they hold at any box.
  """

  @behaviour MilosTraining.Community.Ports.EventStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :community_event_store)

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
  def mark_converted(context, user_id, window, at),
    do: call(context, :mark_converted, [user_id, window, at])
end
