defmodule MilosTraining.Workers.DispatchMessageJob do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 10,
    unique: [period: 86_400, fields: [:worker, :args], keys: [:message_id]]

  alias MilosTraining.Application.DispatchMessageDelivery
  alias MilosTraining.Application.OwnershipKeys
  alias MilosTraining.Organizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, %{"organization_id" => organization_id}} <-
           OwnershipKeys.require_tenant_args(args),
         {:ok, tenant_context} <-
           Organizations.resolve_system_tenant_context(
             organization_id,
             :dispatch_message_delivery,
             %{transport: :oban, worker: __MODULE__ |> Atom.to_string()}
           ) do
      DispatchMessageDelivery.call(tenant_context, args)
    end
  end
end
