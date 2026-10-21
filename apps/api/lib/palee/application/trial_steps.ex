defmodule Palee.Application.TrialSteps do
  @moduledoc """
  A trial's timed steps (ADR-144), run by the scheduler: the reminder before
  the class, the expiry of an ask nobody answered by class time, and the
  follow-up the morning after («Πώς σου φάνηκε;», board 6 Q6). Each one
  re-reads the trial and does nothing if it has moved on.
  """

  alias Palee.Application.Trials, as: TrialUseCases
  alias Palee.{Scheduling, Trials}
  alias Palee.Trials.TrialRequest

  def run(organization_id, trial_id, step) when step in [:reminder, :expire, :follow_up] do
    context = %{organization_id: organization_id}

    case Trials.get_request(context, trial_id) do
      %TrialRequest{} = request -> run_step(step, context, request, DateTime.utc_now())
      nil -> :ok
    end
  end

  defp run_step(:reminder, context, %{status: "booked"} = request, now) do
    if DateTime.compare(request.class_starts_at, now) == :gt,
      do: notify(:trial_reminder, context, request)

    :ok
  end

  defp run_step(:expire, context, %{status: "requested"} = request, now) do
    with {:ok, expired} <- Trials.transition(context, request, :expire, now) do
      TrialUseCases.track_status(context, expired)
      :ok
    end
  end

  defp run_step(:follow_up, context, %{status: "attended"} = request, _now) do
    if is_nil(request.join_interest_at) and is_nil(request.follow_up_dismissed_at),
      do: notify(:trial_follow_up, context, request)

    :ok
  end

  defp run_step(_step, _context, _request, _now), do: :ok

  defp notify(type, context, request) do
    slot = Scheduling.get_slot(context, request.scheduled_class_id)
    TrialUseCases.notify_person(type, context, request, slot)
  end
end
