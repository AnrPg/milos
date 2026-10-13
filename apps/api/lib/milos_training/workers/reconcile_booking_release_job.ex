defmodule MilosTraining.Workers.ReconcileBookingReleaseJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [period: 86_400, fields: [:worker, :args], keys: [:booking_id]]

  alias MilosTraining.Application.{BookingEntitlement, OwnershipKeys}
  alias MilosTraining.{Finance, Notifications}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, _args} <- OwnershipKeys.require_tenant_args(args),
         {:ok, _result} <- transition(args),
         :ok <- maybe_delete_pending_notification(args) do
      :ok
    end
  end

  # ADR-097: late cancellations consume the visit; everything else releases it.
  defp transition(%{"finalize" => true} = args),
    do:
      Finance.finalize_entitlement_source(
        args["user_id"],
        "scheduling",
        args["scheduled_class_id"],
        allowance(args),
        %{reason: args["reason"], idempotency_key: args["idempotency_key"]}
      )

  defp transition(args),
    do:
      Finance.release_entitlement_source(
        args["user_id"],
        "scheduling",
        args["scheduled_class_id"],
        allowance(args),
        %{reason: args["reason"], idempotency_key: args["idempotency_key"]}
      )

  defp allowance(args),
    do: BookingEntitlement.allowance(%{"entitlement_allowance" => args["allowance"]})

  defp maybe_delete_pending_notification(%{
         "delete_pending_notification" => true,
         "booking_id" => id
       }),
       do: Notifications.delete_booking_pending_notifications(id)

  defp maybe_delete_pending_notification(_args), do: :ok
end
