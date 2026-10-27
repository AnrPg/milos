defmodule Palee.Workers.DeliverEmailJob do
  @moduledoc """
  Sends one outbox email (ADR-203). Inserted with its `email_messages` row
  by `Palee.Email.enqueue/4`; the decisions are in
  `Palee.Email.Commands.DeliverEmail`. Exponential backoff (1 minute
  doubling to an hour) over `DeliveryPolicy.max_attempts/0` attempts.
  """

  use Oban.Worker,
    queue: :email,
    max_attempts: Palee.Email.Domain.DeliveryPolicy.max_attempts()

  alias Palee.Email.Domain.DeliveryPolicy

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}} = job) do
    Palee.Email.deliver(message_id, %{
      attempt: job.attempt || 1,
      max_attempts: job.max_attempts || DeliveryPolicy.max_attempts()
    })
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: DeliveryPolicy.backoff(attempt)
end
