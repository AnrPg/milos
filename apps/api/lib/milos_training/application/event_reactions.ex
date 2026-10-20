defmodule MilosTraining.Application.EventReactions do
  @moduledoc """
  How club events follow the rest of the box (ADR-153), as a domain-event
  handler: someone who came to an event and joins the box within
  #{30} days of it counts as converted in the event's numbers. Replays
  change nothing (only unconverted check-ins move).
  """

  @behaviour MilosTraining.DomainEvents.Handler

  alias MilosTraining.Community

  @impl true
  def handle_event(
        :membership_activated,
        %{organization_id: organization_id, user_id: user_id} = event
      ) do
    at = event[:at] || DateTime.utc_now()
    window = %{from: DateTime.add(at, -Community.event_conversion_days(), :day), to: at}
    Community.mark_event_conversions(%{organization_id: organization_id}, user_id, window, at)
    :ok
  end

  def handle_event(_name, _payload), do: :ok
end
