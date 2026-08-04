defmodule MilosTraining.Workers.DispatchMessageJob do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 10,
    unique: [period: 86_400, fields: [:worker, :args], keys: [:message_id]]

  alias MilosTraining.Application.DispatchMessageDelivery
  alias MilosTraining.Application.OwnershipKeys

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, _args} <- OwnershipKeys.require_tenant_args(args) do
      DispatchMessageDelivery.call(args)
    end
  end
end
