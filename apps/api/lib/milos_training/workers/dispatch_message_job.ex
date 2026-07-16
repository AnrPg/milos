defmodule MilosTraining.Workers.DispatchMessageJob do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 10,
    unique: [period: 86_400, fields: [:worker, :args], keys: [:message_id]]

  alias MilosTraining.Application.DispatchMessageDelivery

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: DispatchMessageDelivery.call(args)
end
