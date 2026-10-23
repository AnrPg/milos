defmodule Palee.Community.Commands.Events do
  @moduledoc """
  Events in a club (ADR-153): staff and coaches create, edit and cancel
  them (one occurrence or «this and following»); people say they come or
  not; staff record who paid and who came. Runs in the scope of the gym
  that runs the club. Every change to who holds a place happens with the
  event row locked, so the capacity holds under concurrency, and a freed
  place goes to the waitlist in the same transaction.
  """

  alias Palee.Community.{Event, EventStore}
  alias Palee.Community.Domain.{EventPolicy, EventSeries}

  @live ~w(going waitlisted)

  # Creating and editing -------------------------------------------------------

  @doc """
  A new event in `club`, or a weekly run of them when `repeat_until` (a date
  in the box's zone) is given; every occurrence shares a `series_id`. With
  `channel_id` it is an event of that member group (checked by the caller).
  """
  def create(%{organization_id: organization_id, user_id: user_id} = context, club, attrs, opts) do
    channel_id = Keyword.get(opts, :channel_id)

    attrs =
      attrs
      |> Map.take(Event.editable_fields())
      |> Map.merge(%{
        organization_id: organization_id,
        club_id: club.id,
        channel_id: channel_id,
        created_by_id: user_id
      })

    with :ok <- own_live_club(context, club),
         %Ecto.Changeset{valid?: true} = changeset <- Event.create_changeset(attrs),
         {:ok, times} <- occurrences(changeset, opts) do
      series_id = if length(times) > 1, do: Ecto.UUID.generate()

      times
      |> Enum.map(fn {starts_at, ends_at} ->
        Map.merge(attrs, %{starts_at: starts_at, ends_at: ends_at, series_id: series_id})
      end)
      |> then(&EventStore.insert_events(context, &1))
    else
      %Ecto.Changeset{} = invalid -> {:error, invalid}
      error -> error
    end
  end


  @doc """
  ADR-185: whether the attributes make a valid event, before there is a
  club for it (a person's first own event creates their organisation only
  once this passes).
  """
  def check(attrs) do
    attrs
    |> Map.take(Event.editable_fields())
    |> Map.put(:club_id, Ecto.UUID.generate())
    |> Event.create_changeset()
    |> case do
      %Ecto.Changeset{valid?: true} -> :ok
      invalid -> {:error, invalid}
    end
  end

  defp occurrences(changeset, opts) do
    starts_at = Ecto.Changeset.get_field(changeset, :starts_at)
    ends_at = Ecto.Changeset.get_field(changeset, :ends_at)

    case Keyword.get(opts, :repeat_until) do
      nil ->
        {:ok, [{starts_at, ends_at}]}

      %Date{} = until ->
        EventSeries.weekly(starts_at, ends_at, until, Keyword.fetch!(opts, :zone))
    end
  end

  defp own_live_club(%{organization_id: organization_id}, club) do
    cond do
      club.organization_id != organization_id -> {:error, :not_found}
      not is_nil(Map.get(club, :archived_at)) -> {:error, :not_found}
      club.kind not in ~w(gym open) -> {:error, :not_found}
      true -> :ok
    end
  end

  @doc """
  Edits `event`, or with scope `following` also every later occurrence of
  its series. Following occurrences move as the edited one moved
  (`EventSeries.follow/4`). A raised capacity lets the waitlist in.
  Returns `{:ok, [%{before: event, after: event, promoted: [attendee]}]}`.
  """
  def update(context, event, attrs, scope, opts) do
    attrs = Map.take(attrs, Event.editable_fields())
    zone = Keyword.fetch!(opts, :zone)
    now = Keyword.fetch!(opts, :now)

    with :ok <- not_cancelled(event),
         :ok <- valid_scope(scope),
         %Ecto.Changeset{valid?: true} = changeset <- Event.update_changeset(event, attrs) do
      moved = %{
        starts_at: Ecto.Changeset.get_field(changeset, :starts_at),
        ends_at: Ecto.Changeset.get_field(changeset, :ends_at)
      }

      context
      |> targets(event, scope)
      |> Enum.reduce_while({:ok, []}, fn target, {:ok, done} ->
        times =
          if target.id == event.id,
            do: moved,
            else: EventSeries.follow(target, event, moved, zone)

        case update_one(context, target, Map.merge(attrs, times), now) do
          {:ok, result} -> {:cont, {:ok, [result | done]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, results} -> {:ok, Enum.reverse(results)}
        error -> error
      end
    else
      %Ecto.Changeset{} = invalid -> {:error, invalid}
      error -> error
    end
  end

  defp update_one(context, target, attrs, now) do
    EventStore.with_event_lock(context, target.id, fn locked ->
      attrs =
        if EventPolicy.reset_reminder?(locked, attrs, now),
          do: Map.put(attrs, :reminder_sent_at, nil),
          else: attrs

      with {:ok, updated} <- EventStore.update_event(context, locked, attrs),
           {:ok, promoted} <- promote(context, updated, now) do
        {:ok, %{before: locked, after: updated, promoted: promoted}}
      end
    end)
  end

  @doc "Cancels `event`, or with scope `following` every later live occurrence too."
  def cancel(context, event, scope, reason, now) do
    with :ok <- not_cancelled(event),
         :ok <- valid_scope(scope) do
      context
      |> targets(event, scope)
      |> Enum.reduce_while({:ok, []}, fn target, {:ok, done} ->
        case EventStore.set_event_lifecycle(context, target, %{
               cancelled_at: now,
               cancel_reason: reason
             }) do
          {:ok, cancelled} -> {:cont, {:ok, [cancelled | done]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, cancelled} -> {:ok, Enum.reverse(cancelled)}
        error -> error
      end
    end
  end

  defp targets(context, %{series_id: series_id} = event, "following") when is_binary(series_id) do
    context
    |> EventStore.list_events(%{series_id: series_id, limit: 500})
    |> Enum.filter(&(DateTime.compare(&1.starts_at, event.starts_at) != :lt))
  end

  defp targets(_context, event, _scope), do: [event]

  defp not_cancelled(%{cancelled_at: nil}), do: :ok
  defp not_cancelled(_event), do: {:error, :event_cancelled}

  defp valid_scope(scope),
    do: if(scope in EventPolicy.scopes(), do: :ok, else: {:error, :invalid_scope})

  # Places ---------------------------------------------------------------------

  @doc """
  «Θα έρθω»: a place, or the waitlist when the event is full. `facts` say
  how the person relates to the club (`club_member?`) and who invited them
  (`invited_by`, from a verified invitation). Saying it twice changes
  nothing. Returns `{:ok, %{attendee: attendee, joined: boolean}}`.
  """
  def rsvp(context, event_id, user_id, facts, now) do
    EventStore.with_event_lock(context, event_id, fn event ->
      with :ok <- EventPolicy.open_for_rsvp(event, now),
           {:ok, source} <- EventPolicy.source(Map.put(facts, :open?, event.open_to_non_members)) do
        case EventStore.get_attendee(context, event.id, user_id) do
          %{status: status} = attendee when status in @live ->
            {:ok, %{attendee: attendee, joined: false, event: event}}

          existing ->
            join(context, event, existing, user_id, source, facts, now)
        end
      end
    end)
  end

  defp join(context, event, existing, user_id, source, facts, now) do
    {source, inviter_id} =
      case source do
        {"guest", inviter_id} -> {"guest", inviter_id}
        source -> {source, nil}
      end

    with :ok <- guest_allowed(context, event, inviter_id, Map.get(facts, :host_invite?, false)) do
      going = going_count(context, event.id)

      attrs = %{
        status: EventPolicy.join_status(event, going),
        source: source,
        invited_by_id: inviter_id,
        queued_at: now,
        promoted_at: nil,
        cancelled_at: nil,
        late_cancel: false,
        removed_by_id: nil
      }

      result =
        case existing do
          nil ->
            EventStore.insert_attendee(
              context,
              Map.merge(attrs, %{
                organization_id: event.organization_id,
                event_id: event.id,
                user_id: user_id
              })
            )

          attendee ->
            EventStore.update_attendee(context, attendee, attrs)
        end

      with {:ok, attendee} <- result, do: {:ok, %{attendee: attendee, joined: true, event: event}}
    end
  end

  defp guest_allowed(_context, _event, nil, _host?), do: :ok

  # ADR-185: the host's own link is not a guest pass.
  defp guest_allowed(_context, event, _inviter_id, true),
    do: EventPolicy.invite_check(event, :host, nil, 0)

  defp guest_allowed(context, event, inviter_id, false) do
    inviter_status =
      case EventStore.get_attendee(context, event.id, inviter_id) do
        %{status: status} -> status
        nil -> nil
      end

    EventPolicy.guest_check(
      event,
      inviter_status,
      EventStore.count_guests(context, event.id, inviter_id)
    )
  end

  @doc """
  «Δεν θα έρθω» (`actor_id` is the person) or staff freeing a place
  (`actor_id` is staff): the place goes to the first on the waitlist.
  Returns `{:ok, %{attendee: attendee, promoted: [attendee], event: event}}`.
  """
  def withdraw(context, event_id, user_id, actor_id, now) do
    EventStore.with_event_lock(context, event_id, fn event ->
      self? = actor_id == user_id

      with :ok <- if(self?, do: EventPolicy.open_for_rsvp(event, now), else: :ok),
           %{status: status} = attendee when status in @live <-
             EventStore.get_attendee(context, event.id, user_id) || {:error, :not_found},
           {:ok, cancelled} <-
             EventStore.update_attendee(context, attendee, %{
               status: "cancelled",
               cancelled_at: now,
               late_cancel: self? and EventPolicy.late_cancel?(status, event, now),
               removed_by_id: if(self?, do: nil, else: actor_id)
             }),
           {:ok, promoted} <-
             if(status == "going", do: promote(context, event, now), else: {:ok, []}) do
        {:ok, %{attendee: cancelled, promoted: promoted, event: event}}
      else
        %{status: "cancelled"} -> {:error, :not_found}
        error -> error
      end
    end)
  end

  # Free places go to the waitlist in queue order, until the start.
  defp promote(context, event, now) do
    if is_nil(event.cancelled_at) and DateTime.compare(event.starts_at, now) == :gt do
      waiting = EventStore.list_attendees(context, [event.id], ["waitlisted"])

      event
      |> EventPolicy.promotions(going_count(context, event.id), waiting)
      |> Enum.reduce_while({:ok, []}, fn attendee, {:ok, done} ->
        case EventStore.update_attendee(context, attendee, %{status: "going", promoted_at: now}) do
          {:ok, promoted} -> {:cont, {:ok, [promoted | done]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, promoted} -> {:ok, Enum.reverse(promoted)}
        error -> error
      end
    else
      {:ok, []}
    end
  end

  defp going_count(context, event_id) do
    context |> EventStore.attendee_counts([event_id]) |> get_in([event_id, "going"]) || 0
  end

  # Staff --------------------------------------------------------------------

  @doc "Ήρθε (or undoing it) for someone holding a place."
  def check_in(%{user_id: actor_id} = context, event, user_id, on?, now) do
    with %{} = attendee <-
           EventStore.get_attendee(context, event.id, user_id) || {:error, :not_found},
         :ok <- if(on?, do: EventPolicy.check_in_check(event, attendee), else: :ok) do
      EventStore.update_attendee(
        context,
        attendee,
        if(on?,
          do: %{checked_in_at: attendee.checked_in_at || now, checked_in_by_id: actor_id},
          else: %{checked_in_at: nil, checked_in_by_id: nil}
        )
      )
    end
  end

  @doc """
  «Πλήρωσε»: records a payment for a place once. `record` (the event and the
  attendee → `{:ok, %{finance_invoice_id, finance_payment_id}}`) writes it
  where the box keeps its money, inside the same transaction, so a failure
  there records nothing here and a second press finds it already paid.
  """
  def record_payment(%{user_id: actor_id} = context, event_id, user_id, method, now, record) do
    EventStore.with_event_lock(context, event_id, fn event ->
      with %{} = attendee <-
             EventStore.get_attendee(context, event.id, user_id) || {:error, :not_found},
           :ok <- EventPolicy.payment_check(event, attendee),
           {:ok, finance} <- record.(event, attendee) do
        EventStore.update_attendee(context, attendee, %{
          paid_at: now,
          paid_recorded_by_id: actor_id,
          payment_method: method,
          amount_cents: event.price_cents,
          finance_invoice_id: finance[:finance_invoice_id],
          finance_payment_id: finance[:finance_payment_id]
        })
      end
    end)
  end

  @doc """
  ADR-185: records a refund of a recorded payment once (all of it unless
  `amount_cents` says less), with the event locked.
  """
  def record_refund(%{user_id: actor_id} = context, event_id, user_id, amount_cents, now) do
    EventStore.with_event_lock(context, event_id, fn event ->
      with %{} = attendee <-
             EventStore.get_attendee(context, event.id, user_id) || {:error, :not_found},
           amount = EventPolicy.refund_amount(attendee, amount_cents),
           :ok <- EventPolicy.refund_check(attendee, amount) do
        EventStore.update_attendee(context, attendee, %{
          refunded_at: now,
          refund_cents: amount,
          refunded_by_id: actor_id
        })
      end
    end)
  end

  @doc "Stamps a once-only step (`:reminder_sent_at`, `:trial_offer_sent_at`) on the event."
  def claim(context, event_id, field, now),
    do: EventStore.claim_event(context, event_id, field, now)

  @doc "Remembers that `attendees` got the trial offer."
  def mark_trial_offered(context, attendees, now) do
    Enum.each(attendees, &EventStore.update_attendee(context, &1, %{trial_offered_at: now}))
  end
end
