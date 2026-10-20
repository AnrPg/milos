defmodule MilosTraining.Application.StaffCommunityEvents do
  @moduledoc """
  «Κοινότητα › Events» for staff (ADR-153, board 8): the box's events with
  their numbers; creating, editing and cancelling them; the attendee list
  (going, waitlist, guests, paid, came) with «Ήρθε», «Πλήρωσε» and freeing a
  place; «Μήνυμα σε όλους»; and the one trial offer after the event to the
  people who came and are not members.

  Runs in the gym's tenant context. Who may do what: `manage_events` runs
  events; the desk (`check_in`) marks who came and the till
  (`take_payments`) records payments, so front desk staff can work the
  door of an event they don't organise.
  """

  alias MilosTraining.Application.{
    ClubScope,
    CommunityEvents,
    CommunityPeople,
    EventNotices,
    EventPresenter
  }

  alias MilosTraining.{Community, Organizations, Trials}

  @read [:manage_events, :check_in, :take_payments]
  @past_limit 50
  @upcoming_limit 200
  @message_max 500

  @doc "Upcoming (default) or past events of the box, each with its numbers."
  def list(%{organization_id: organization_id} = context, params, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context, @read),
         {:ok, clubs} <- clubs(context) do
      filter =
        case params[:scope] do
          "past" -> %{ended_before: now, order: :desc, limit: @past_limit}
          _upcoming -> %{from: now, limit: @upcoming_limit}
        end

      events =
        Community.list_events(
          context,
          Map.merge(filter, %{organization_ids: [organization_id], include_cancelled: true})
        )

      stats = stats(context, events, now)

      {:ok,
       %{
         events:
           events
           |> present(context, clubs, now)
           |> Enum.map(&Map.put(&1, :stats, Map.fetch!(stats, &1.id)))
       }}
    end
  end

  @doc "Creates an event (or a weekly run) in one of the box's clubs."
  def create(context, params) do
    with :ok <- authorize(context, [:manage_events]),
         {:ok, clubs} <- clubs(context),
         %{} = club <- Enum.find(clubs, &(&1.id == params[:club_id])) || {:error, :not_found},
         {:ok, [first | _] = events} <- CommunityEvents.manage_create(context, club, params),
         {:ok, shown} <- show(context, first.id) do
      {:ok, %{event: shown, occurrences: length(events)}}
    end
  end

  def update(context, event_id, params) do
    with :ok <- authorize(context, [:manage_events]),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         {:ok, _updated} <- CommunityEvents.manage_update(context, event, params),
         do: show(context, event.id)
  end

  def cancel(context, event_id, params) do
    with :ok <- authorize(context, [:manage_events]),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         {:ok, _cancelled} <- CommunityEvents.manage_cancel(context, event, params),
         do: show(context, event.id)
  end

  @doc """
  An event with its attendees in groups (going, waitlisted, cancelled), who
  invited each guest, who paid and who came, whether each person is a
  member of the box, the numbers, and where the trial offer stands.
  """
  def show(%{organization_id: organization_id} = context, event_id, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context, @read),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         {:ok, clubs} <- clubs(context) do
      attendees = Community.list_attendees(context, [event.id])
      members = MapSet.new(Organizations.list_active_membership_user_ids(organization_id))

      people =
        CommunityPeople.by_ids(
          Enum.flat_map(attendees, &[&1.user_id, &1.invited_by_id, &1.removed_by_id])
        )

      since = DateTime.add(now, -Community.event_late_cancel_window_days(), :day)

      late =
        Community.late_cancel_counts(
          context,
          attendees |> Enum.map(& &1.user_id) |> Enum.uniq(),
          since
        )

      rows = Enum.map(attendees, &attendee_row(&1, people, members, late))
      [shown] = present([event], context, clubs, now)
      offer_to = Community.event_trial_offer_recipients(attendees, MapSet.to_list(members))

      {:ok,
       Map.merge(shown, %{
         stats: Map.fetch!(stats(context, [event], now), event.id),
         attendees: %{
           going: Enum.filter(rows, &(&1.status == "going")),
           waitlisted: Enum.filter(rows, &(&1.status == "waitlisted")),
           cancelled: Enum.filter(rows, &(&1.status == "cancelled"))
         },
         trial_offer: %{
           sent_at: event.trial_offer_sent_at,
           can_send: Community.event_trial_offer_check(event, now) == :ok and offer_to != [],
           recipients: length(offer_to)
         }
       })}
    end
  end

  @doc "«Ήρθε» (on) or undoing it (off)."
  def check_in(context, event_id, user_id, on?) do
    with :ok <- authorize(context, [:manage_events, :check_in]),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         {:ok, _attendee} <-
           Community.check_in_attendee(context, event, user_id, on?, DateTime.utc_now()) do
      CommunityEvents.announce(event)
      show(context, event.id)
    end
  end

  @doc """
  «Πλήρωσε»: records the payment once. When the person has a Finance record
  at the box, Finance issues the receipt (`Ports.EventPayments`).
  """
  def mark_paid(context, event_id, user_id, method) do
    now = DateTime.utc_now()

    with :ok <- authorize(context, [:manage_events, :take_payments]),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         true <- method in Community.event_payment_methods() || {:error, :bad_request},
         {:ok, _attendee} <-
           Community.record_event_payment(context, event.id, user_id, method, now, fn locked,
                                                                                      attendee ->
             event_payments().record(context, %{
               user_id: attendee.user_id,
               amount_cents: locked.price_cents,
               currency: locked.currency,
               method: method,
               description: payment_description(locked),
               recorded_by_id: context.user_id,
               reference: "community_event_attendee:#{attendee.id}"
             })
           end) do
      show(context, event.id)
    end
  end

  @doc "Frees someone's place (an unpaid hold, a no-show to be): the waitlist moves up."
  def remove(%{user_id: actor_id} = context, event_id, user_id) do
    with :ok <- authorize(context, [:manage_events]),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         {:ok, %{promoted: promoted}} <-
           Community.withdraw_from_event(context, event.id, user_id, actor_id, DateTime.utc_now()) do
      EventNotices.promoted(event, promoted)
      CommunityEvents.announce(event)
      show(context, event.id)
    end
  end

  @doc "«Μήνυμα σε όλους»: a notification to everyone going."
  def message(%{user_id: actor_id} = context, event_id, body) do
    body = if is_binary(body), do: String.trim(body), else: ""

    with :ok <- authorize(context, [:manage_events]),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         true <- (body != "" and String.length(body) <= @message_max) || {:error, :bad_request} do
      recipients =
        context
        |> Community.list_attendees([event.id], ["going"])
        |> Enum.reject(&(&1.user_id == actor_id))

      EventNotices.message(event, recipients, body, DateTime.utc_now())
      {:ok, %{sent: length(recipients)}}
    end
  end

  @doc """
  The one trial offer, after the event ended, to the people who came and are
  not members of the box: a notification opening the box's trial sheet with
  the event as its source. Needs a published box page with trials on.
  """
  def trial_offer(%{organization_id: organization_id} = context, event_id) do
    now = DateTime.utc_now()

    with :ok <- authorize(context, [:manage_events]),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         :ok <- Community.event_trial_offer_check(event, now),
         %{} = box <-
           organization_id |> List.wrap() |> Organizations.public_boxes() |> List.first() ||
             {:error, :trials_disabled},
         true <- Trials.policy(context).enabled || {:error, :trials_disabled},
         members = Organizations.list_active_membership_user_ids(organization_id),
         attendees = Community.list_attendees(context, [event.id], ["going"]),
         [_ | _] = recipients <- Community.event_trial_offer_recipients(attendees, members),
         {:ok, claimed} <- claim_offer(context, event.id, now) do
      Community.mark_trial_offered(context, recipients, now)
      EventNotices.trial_offer(claimed, recipients, box)
      {:ok, %{sent: length(recipients)}}
    else
      [] -> {:error, :nobody_to_offer}
      error -> error
    end
  end

  defp claim_offer(context, event_id, now) do
    case Community.claim_event_step(context, event_id, :trial_offer_sent_at, now) do
      {:ok, event} -> {:ok, event}
      {:error, :already_claimed} -> {:error, :trial_offer_already_sent}
    end
  end

  # ------------------------------------------------------------------ internals

  defp stats(context, events, now) do
    ids = Enum.map(events, & &1.id)
    attendees = context |> Community.list_attendees(ids) |> Enum.group_by(& &1.event_id)
    trials = Trials.referral_event_stats(context, ids)

    Map.new(events, fn event ->
      requests = trials |> Map.get(event.id, %{}) |> Map.values() |> Enum.sum()
      {event.id, Community.event_stats(event, Map.get(attendees, event.id, []), requests, now)}
    end)
  end

  defp attendee_row(attendee, people, members, late) do
    %{
      person: CommunityPeople.person(people, attendee.user_id),
      status: attendee.status,
      source: attendee.source,
      invited_by:
        attendee.invited_by_id && CommunityPeople.person(people, attendee.invited_by_id),
      member: MapSet.member?(members, attendee.user_id),
      queued_at: attendee.queued_at,
      promoted_at: attendee.promoted_at,
      paid_at: attendee.paid_at,
      payment_method: attendee.payment_method,
      amount_cents: attendee.amount_cents,
      receipt_issued: not is_nil(attendee.finance_invoice_id),
      checked_in_at: attendee.checked_in_at,
      cancelled_at: attendee.cancelled_at,
      late_cancel: attendee.late_cancel,
      late_cancels_90d: Map.get(late, attendee.user_id, 0),
      removed_by:
        attendee.removed_by_id && CommunityPeople.person(people, attendee.removed_by_id),
      trial_offered_at: attendee.trial_offered_at,
      converted_at: attendee.converted_at
    }
  end

  defp present(
         events,
         %{user_id: user_id, organization_id: organization_id} = context,
         clubs,
         now
       ) do
    managed = if Organizations.can?(context, :manage_events), do: [organization_id], else: []

    EventPresenter.present(events, EventPresenter.viewer(user_id, clubs, managed), now: now)
  end

  # The box's clubs as its staff see them: the gym club and its open clubs.
  defp clubs(%{organization_id: organization_id} = context) do
    with {:ok, clubs} <- ClubScope.call(context),
         do: {:ok, Enum.filter(clubs, &(&1.organization_id == organization_id))}
  end

  defp authorize(context, capabilities) do
    if Enum.any?(capabilities, &Organizations.can?(context, &1)),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp payment_description(event) do
    date =
      event
      |> EventNotices.event_when()
      |> String.split(" ")
      |> List.first()

    String.slice("#{event.title} · #{date}", 0, 200)
  end

  defp event_payments, do: Application.fetch_env!(:milos_training, :event_payments)
end
