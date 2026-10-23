defmodule Palee.Community.Domain.CohostPolicy do
  @moduledoc """
  Co-hosting (ADR-185 §5, D3). Pure.

  * An event has one host organisation (its `organization_id`) and any
    number of co-host organisations, up to #{10}.
  * The host invites a published box; staff with `manage_events` there
    accept or decline. Answering a weekly event's request answers every
    later occurrence's too.
  * Only an upcoming, uncancelled event that is not for a member group
    only can take co-hosts; a box never co-hosts its own event.
  * An accepted co-host shows the event on its box page's Events tab (when
    open to everyone) and in its Feed, its members belong to the event's
    audience, and its staff may send their own trial offer once the event
    is over, to the people who came and are not members of the co-host.
  * The host can take a co-host off; the co-host can withdraw. Either way
    the card stays in the co-host's feed but no longer shows the event.
  """

  alias Palee.Community.Domain.EventPolicy

  @max_cohosts 10
  @answers ~w(accepted declined)

  def max_cohosts, do: @max_cohosts
  def answers, do: @answers

  @doc """
  Whether the host may invite `cohost_organization_id` to `event`. `taken`
  is how many co-hosts are pending or accepted; `existing` the status of a
  row for that box, if any.
  """
  def invite_check(event, cohost_organization_id, taken, existing, now) do
    cond do
      cohost_organization_id == event.organization_id -> {:error, :cannot_cohost_own_event}
      not is_nil(event.cancelled_at) -> {:error, :event_cancelled}
      DateTime.compare(event.ends_at, now) != :gt -> {:error, :event_started}
      EventPolicy.group_only?(event) -> {:error, :group_event}
      existing in ~w(pending accepted) -> {:error, :already_invited}
      taken >= @max_cohosts -> {:error, :cohost_limit_reached}
      true -> :ok
    end
  end

  @doc "Whether a request can be answered: pending, or accepted for a withdrawal."
  def answer_check("pending", answer) when answer in @answers, do: :ok
  def answer_check("accepted", "removed"), do: :ok
  def answer_check(_status, _answer), do: {:error, :not_pending}

  @doc """
  The co-host's own trial offer: the co-host still accepted, the event
  over and not cancelled, and not sent yet (`facts` from the co-host's view).
  """
  def trial_offer_check(%{status: "accepted"} = facts, now) do
    EventPolicy.trial_offer_check(
      %{
        cancelled_at: facts.cancelled_at,
        trial_offer_sent_at: facts.trial_offer_sent_at,
        ends_at: facts.ends_at
      },
      now
    )
  end

  def trial_offer_check(_facts, _now), do: {:error, :not_found}

  @doc "Who gets the co-host's offer: people who came and are not its members."
  def trial_offer_recipients(came_user_ids, member_ids) do
    members = MapSet.new(member_ids)
    came_user_ids |> Enum.uniq() |> Enum.reject(&MapSet.member?(members, &1))
  end

  @doc "The co-host's view of a request, for the inbox: whether it can still be answered."
  def answerable?(%{status: "pending", cancelled_at: nil, ends_at: ends_at}, now),
    do: DateTime.compare(ends_at, now) == :gt

  def answerable?(_request, _now), do: false
end
