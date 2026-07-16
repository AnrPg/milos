defmodule MilosTraining.Workers.ReconcileBookingReleaseJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [period: 86_400, fields: [:worker, :args], keys: [:booking_id]]

  alias MilosTraining.{Finance, Notifications}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, _result} <-
           Finance.release_entitlement_source(
             args["user_id"],
             "scheduling",
             args["scheduled_class_id"],
             :class_visits,
             %{
               reason: args["reason"],
               idempotency_key: args["idempotency_key"]
             }
           ),
         :ok <- maybe_delete_pending_notification(args) do
      :ok
    end
  end

  defp maybe_delete_pending_notification(%{
         "delete_pending_notification" => true,
         "booking_id" => id
       }),
       do: Notifications.delete_booking_pending_notifications(id)

  defp maybe_delete_pending_notification(_args), do: :ok
end
