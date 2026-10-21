defmodule Palee.Appointments.Ports.AppointmentStore do
  @moduledoc "Persistence port of the Appointments context (ADR-098)."

  @callback create_slot(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_slot(map(), binary()) :: map() | nil
  @callback list_slots(map(), map()) :: [map()]
  @callback cancel_slot(map(), binary()) :: {:ok, map()} | {:error, term()}
  @callback create_booking(map(), map(), (map(), [map()] -> :ok | {:error, term()})) ::
              {:ok, map()} | {:error, term()}
  @callback get_booking(map(), binary()) :: map() | nil
  @callback list_bookings(map(), map()) :: [map()]
  @callback cancel_booking(map(), binary(), boolean()) :: {:ok, map()} | {:error, term()}
  @callback record_attendance(map(), binary(), String.t()) :: {:ok, map()} | {:error, term()}
end
