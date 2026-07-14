defmodule MilosTraining.Notifications.Ports.PushSubscriptionStore do
  @callback save_push_subscription(map()) ::
              {:ok, map(), :created | :updated} | {:error, Ecto.Changeset.t()}
  @callback list_push_subscriptions(Ecto.UUID.t()) :: [map()]
  @callback get_push_subscription(Ecto.UUID.t(), String.t()) :: map() | nil
  @callback delete_push_subscription(Ecto.UUID.t(), String.t()) :: boolean()
end
