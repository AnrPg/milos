defmodule MilosTraining.Workers.BookingTimeoutJob do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MilosTraining.Application.TimeoutBooking

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id, "booking_id" => booking_id}
      }) do
    case TimeoutBooking.call(organization_id, booking_id) do
      {:ok, _booking} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:error, :missing_organization_scope}
end
