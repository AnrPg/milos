defmodule MilosTraining.Notifications.Ports.NativePushTokenStore do
  @moduledoc "Persistence of the store apps' push tokens (ADR-171)."

  @callback save_native_push_token(map()) ::
              {:ok, map(), :created | :updated} | {:error, Ecto.Changeset.t()}
  @callback list_native_push_tokens(Ecto.UUID.t()) :: [map()]
  @callback get_native_push_token(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback delete_native_push_token(Ecto.UUID.t(), String.t()) :: boolean()
  @callback delete_native_push_token_by_id(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
end
