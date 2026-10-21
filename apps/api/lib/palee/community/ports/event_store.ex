defmodule Palee.Community.Ports.EventStore do
  @moduledoc """
  Persistence port for club events and their attendees (ADR-153). Every call
  runs in the caller's `RepoContext`: the gym's scope for everything about
  its events, a person's own session for the places they hold at any box.
  """

  alias Palee.Community.{Event, EventAttendee}

  @type context :: map()
  @type id :: binary()

  @type event_filter :: %{
          optional(:organization_ids) => [id()],
          optional(:ids) => [id()],
          optional(:cover_media_id) => id(),
          optional(:club_ids) => [id()],
          optional(:series_id) => id(),
          optional(:from) => DateTime.t(),
          optional(:to) => DateTime.t(),
          optional(:ended_before) => DateTime.t(),
          optional(:open_only) => boolean(),
          optional(:good_for_friends) => boolean(),
          optional(:include_cancelled) => boolean(),
          optional(:order) => :asc | :desc,
          optional(:limit) => pos_integer()
        }

  @doc "Inserts every occurrence of a new event in one transaction."
  @callback insert_events(context(), [map()]) :: {:ok, [Event.t()]} | {:error, term()}
  @callback get_event(context(), id()) :: Event.t() | nil
  @callback list_events(context(), event_filter()) :: [Event.t()]
  @callback update_event(context(), Event.t(), map()) ::
              {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  @callback set_event_lifecycle(context(), Event.t(), map()) ::
              {:ok, Event.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Stamps `field` (`:reminder_sent_at`, `:trial_offer_sent_at`) on the event
  only if it is still empty, so a step runs exactly once.
  """
  @callback claim_event(context(), id(), atom(), DateTime.t()) ::
              {:ok, Event.t()} | {:error, :already_claimed}

  @doc "Events that start within `window` and still owe their reminder."
  @callback reminders_due(context(), %{from: DateTime.t(), to: DateTime.t()}) :: [Event.t()]

  @doc """
  Runs `fun` with the event row locked (`FOR UPDATE`) in one transaction:
  every change to who holds a place on the event queues here, so the
  capacity holds under concurrency. An `{:error, _}` result rolls back.
  """
  @callback with_event_lock(context(), id(), (Event.t() -> result)) :: result | {:error, term()}
            when result: term()

  @callback get_attendee(context(), id(), id()) :: EventAttendee.t() | nil

  @doc "Attendees of the events, in queue order, optionally narrowed by status."
  @callback list_attendees(context(), [id()], [String.t()] | nil) :: [EventAttendee.t()]

  @doc "Going and waitlisted counts per event."
  @callback attendee_counts(context(), [id()]) :: %{id() => %{String.t() => non_neg_integer()}}

  @doc "Guests a member brought to an event who still hold or wait for a place."
  @callback count_guests(context(), id(), id()) :: non_neg_integer()

  @callback insert_attendee(context(), map()) ::
              {:ok, EventAttendee.t()} | {:error, Ecto.Changeset.t()}
  @callback update_attendee(context(), EventAttendee.t(), map()) ::
              {:ok, EventAttendee.t()} | {:error, Ecto.Changeset.t()}

  @doc "A person's own attendee rows at every box (their personal session)."
  @callback attendances_of(context(), id(), [String.t()]) :: [EventAttendee.t()]
  @callback late_cancel_counts(context(), [id()], DateTime.t()) :: %{id() => non_neg_integer()}

  @doc """
  Marks as converted the person's check-ins at the box's events that ended
  between `from` and `to` (they joined the box). Returns how many changed.
  """
  @callback mark_converted(context(), id(), %{from: DateTime.t(), to: DateTime.t()}, DateTime.t()) ::
              non_neg_integer()
end
