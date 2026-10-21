defmodule Palee.Application.TrialReactions do
  @moduledoc """
  How trials follow the rest of the box (ADR-144), as domain-event handlers:

    * attendance on the roster marks the trial Ήρθε / Δεν ήρθε;
    * a trial seat cancelled anywhere (the person, staff) or its class
      deleted cancels the trial;
    * joining the box within #{30} days of a trial converts it (board 6 Q6).

  Each reaction re-reads the trial and skips steps the trial can't take, so
  replays and out-of-order events change nothing.
  """

  @behaviour Palee.DomainEvents.Handler

  require Logger

  alias Palee.Application.Trials, as: TrialUseCases
  alias Palee.Trials
  alias Palee.Trials.TrialRequest

  @conversion_days 30

  @impl true
  def handle_event(
        :attendance_recorded,
        %{organization_id: organization_id, booking_id: booking_id} = event
      )
      when is_binary(booking_id) do
    context = %{organization_id: organization_id}

    with %TrialRequest{} = request <- Trials.get_request_by_booking(context, booking_id),
         step when not is_nil(step) <- attendance_step(event.status) do
      step(context, request, step, event[:at] || DateTime.utc_now())
    end

    :ok
  end

  def handle_event(:booking_cancelled, %{
        organization_id: organization_id,
        booking_id: booking_id,
        kind: "trial"
      }) do
    context = %{organization_id: organization_id}

    case Trials.get_request_by_booking(context, booking_id) do
      %TrialRequest{status: status} = request ->
        if Trials.open?(status), do: TrialUseCases.cancel_request(context, request)

      nil ->
        :ok
    end

    :ok
  end

  # The class is gone: open trials in it end, and a booked person hears why.
  def handle_event(:class_cancelled, %{
        organization_id: organization_id,
        scheduled_class_id: slot_id
      }) do
    context = %{organization_id: organization_id}

    context
    |> Trials.list_requests(%{scheduled_class_id: slot_id, statuses: Trials.open_statuses()})
    |> Enum.each(fn request ->
      with {:ok, cancelled} <- TrialUseCases.cancel_request(context, request),
           "booked" <- request.status do
        TrialUseCases.notify_person(:trial_class_cancelled, context, cancelled, nil)
      end
    end)

    :ok
  end

  def handle_event(
        :membership_activated,
        %{organization_id: organization_id, user_id: user_id} = event
      ) do
    context = %{organization_id: organization_id}
    at = event[:at] || DateTime.utc_now()

    context
    |> Trials.list_requests(%{
      user_id: user_id,
      statuses: ~w(booked attended no_show),
      from: DateTime.add(at, -@conversion_days, :day)
    })
    |> Enum.each(&step(context, &1, :convert, at))

    :ok
  end

  def handle_event(_name, _payload), do: :ok

  defp attendance_step(status) when status in ["attended", :attended], do: :attend
  defp attendance_step(status) when status in ["no_show", :no_show], do: :no_show
  defp attendance_step(_status), do: nil

  defp step(context, request, step, at) do
    case Trials.transition(context, request, step, at) do
      {:ok, updated} ->
        TrialUseCases.track_status(context, updated)

      {:error, :invalid_trial_transition} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "trial_reaction_failed step=#{step} trial=#{request.id} #{inspect(reason)}"
        )
    end
  end
end
