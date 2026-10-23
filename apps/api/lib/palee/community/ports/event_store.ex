defmodule Palee.Community.Ports.EventStore do
  @moduledoc """
  Persistence port for club events and their attendees (ADR-153). Every call
  runs in the caller's `RepoContext`: the gym's scope for everything about
  its events, a person's own session for the places they hold at any box.
  """

  alias Palee.Community.{Event, EventAttendee, EventCohost}

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

  # ADR-185 ----------------------------------------------------------------

  @doc """
  How many distinct events (a weekly run once) the organisation created
  since `since`, and how many live occurrences it has ahead of `now`.
  """
  @callback creation_counts(context(), DateTime.t(), DateTime.t()) :: %{
              created_last_day: non_neg_integer(),
              upcoming: non_neg_integer()
            }

  @doc "Co-host rows of events (the host's tenant), oldest first."
  @callback list_cohosts(context(), [id()]) :: [EventCohost.t()]
  @callback get_cohost(context(), id()) :: EventCohost.t() | nil
  @callback insert_cohost(context(), map()) :: {:ok, EventCohost.t()} | {:error, term()}
  @callback update_cohost(context(), EventCohost.t(), map()) ::
              {:ok, EventCohost.t()} | {:error, term()}

  @doc """
  The co-host side, through definer functions: requests to a box (for
  whoever runs its events there), answering one, which boxes co-host which
  events (accepted), whether a box co-hosts an event, and a co-host's
  trial offer facts and claim.
  """
  @callback cohost_requests(context(), id()) :: [map()]
  @callback respond_cohost(context(), id(), String.t(), DateTime.t()) :: [map()]
  @callback accepted_cohosts(context(), [id()] | nil, [id()] | nil) :: [map()]
  @callback cohosted_by?(context(), id(), id()) :: boolean()
  @callback cohost_trial_offer_facts(context(), id()) :: map() | nil
  @callback claim_cohost_trial_offer(context(), id(), DateTime.t()) :: boolean()

  @doc "Counts a page open; `viewer_key` dedupes the viewer for the day."
  @callback record_view(context(), id(), Date.t(), binary()) :: :ok
  @doc "Opens and distinct viewers per event, summed over its days."
  @callback view_totals(context(), [id()]) :: %{
              id() => %{views: non_neg_integer(), viewers: non_neg_integer()}
            }

  @doc "Organiser organisations created before `before` that never got an event."
  @callback empty_organiser_organization_ids(context(), DateTime.t()) :: [id()]
end
