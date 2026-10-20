defmodule MilosTraining.Workers.ReconcileBookingReleaseJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [period: 86_400, fields: [:worker, :args], keys: [:booking_id]]

  alias MilosTraining.Application.{BookingEntitlement, OwnershipKeys}
  alias MilosTraining.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, _args} <- OwnershipKeys.require_tenant_args(args),
         {:ok, _result} <- transition(args),
         :ok <- maybe_delete_pending_notification(args) do
      :ok
    end
  end

  # ADR-097: late cancellations consume the visit; everything else releases it.
  # TD-092: the job has no session scope of its own; the ledger transition runs
  # in the booking's organization (unscoped, RLS hid the reservation and the
  # retry silently did nothing).
  defp transition(%{"finalize" => true} = args),
    do:
      BookingEntitlement.finalize(
        tenant(args),
        args["user_id"],
        args["scheduled_class_id"],
        allowance(args),
        %{reason: args["reason"], idempotency_key: args["idempotency_key"]}
      )

  defp transition(args),
    do:
      BookingEntitlement.release(
        tenant(args),
        args["user_id"],
        args["scheduled_class_id"],
        allowance(args),
        %{reason: args["reason"], idempotency_key: args["idempotency_key"]}
      )

  defp tenant(args), do: %{organization_id: args["organization_id"]}

  defp allowance(args),
    do: BookingEntitlement.allowance(%{"entitlement_allowance" => args["allowance"]})

  defp maybe_delete_pending_notification(%{
         "delete_pending_notification" => true,
         "organization_id" => organization_id,
         "booking_id" => id
       }),
       do: Notifications.delete_booking_pending_notifications(organization_id, id)

  defp maybe_delete_pending_notification(_args), do: :ok
end
