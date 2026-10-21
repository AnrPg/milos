defmodule Palee.Notifications.Ports.PushDispatcher do
  @callback send_push(map(), map()) :: :ok | {:error, term()}
end
