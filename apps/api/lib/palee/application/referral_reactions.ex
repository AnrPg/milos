defmodule Palee.Application.ReferralReactions do
  @moduledoc """
  How invites follow the rest of the box (ADR-156), as domain-event
  handlers: a friend who came to an event, came to a class, joined the box
  or paid for their first package moves their invite one step, and the
  invite qualifies when it reaches the step its programme rewards.
  `Referrals.step/4` re-reads the invite under a lock, so replays and
  out-of-order events change nothing.
  """

  @behaviour Palee.DomainEvents.Handler

  alias Palee.Application.Referrals

  @impl true
  def handle_event(:event_attendance_recorded, %{organization_id: org, user_id: user} = event),
    do: step(org, user, :event, event)

  # Any class the friend came to before joining is their trial (a trial seat,
  # a guest pass or a drop-in).
  def handle_event(
        :attendance_recorded,
        %{organization_id: org, user_id: user, status: status} = event
      )
      when status in ["attended", :attended],
      do: step(org, user, :trial, event)

  def handle_event(:membership_activated, %{organization_id: org, user_id: user} = event),
    do: step(org, user, :joined, event)

  def handle_event(:membership_payment_recorded, %{organization_id: org, user_id: user} = event),
    do: step(org, user, :paid, event)

  def handle_event(_name, _payload), do: :ok

  defp step(organization_id, user_id, step, event)
       when is_binary(organization_id) and is_binary(user_id) do
    Referrals.step(organization_id, user_id, step, event[:at] || DateTime.utc_now())
    :ok
  end

  defp step(_organization_id, _user_id, _step, _event), do: :ok
end
