defmodule MilosTraining.Application.AppointmentLedger do
  @moduledoc false
  # Finance side of an appointment booking (ADR-098): the reservation made at
  # booking time is finalized when the session is used and released otherwise.

  alias MilosTraining.{Finance, Scheduling}

  def finalize(context, booking, reason), do: close(context, booking, :finalize, reason)
  def release(context, booking, reason), do: close(context, booking, :release, reason)

  defp close(_context, %{reservation_id: nil}, _action, _reason), do: :ok

  defp close(context, %{reservation_id: reservation_id, id: id}, action, reason) do
    params = %{reason: reason, idempotency_key: "appointment-#{action}:#{id}"}

    _result =
      case action do
        :finalize -> Finance.finalize_entitlement(context, reservation_id, params)
        :release -> Finance.release_entitlement(context, reservation_id, params)
      end

    :ok
  end

  @doc "Cancellation cutoff for the client: the paying package's, else the gym default."
  def cutoff_hours(context, terms) do
    case terms && terms[:cancellation_cutoff_hours] do
      hours when is_integer(hours) ->
        hours

      _none ->
        context
        |> Scheduling.get_settings()
        |> Map.get(:default_cancellation_cutoff_hours)
    end
  end
end
