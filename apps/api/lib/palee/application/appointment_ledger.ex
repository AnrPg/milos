defmodule Palee.Application.AppointmentLedger do
  @moduledoc false
  # Finance side of an appointment booking (ADR-098): the reservation made at
  # booking time is finalized when the session is used and released otherwise.

  alias Palee.{Finance, Scheduling}

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

  @doc """
  Cancellation cutoff for the client in minutes (ADR-222): the paying
  package's, else the gym default.
  """
  def cutoff_minutes(context, terms) do
    case terms && terms[:cancellation_cutoff_hours] do
      hours when is_integer(hours) ->
        hours * 60

      _none ->
        context
        |> Scheduling.get_settings()
        |> Map.get(:default_cancellation_cutoff_minutes)
    end
  end
end
