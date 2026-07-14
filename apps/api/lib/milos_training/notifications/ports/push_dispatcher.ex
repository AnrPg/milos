defmodule MilosTraining.Notifications.Ports.PushDispatcher do
  @callback send_push(map(), map()) :: :ok | {:error, term()}
end
