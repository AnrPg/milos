defmodule MilosTraining.Application.Ports.ProviderToday do
  @moduledoc """
  One provider's «Σήμερα» items for the member (ADR-162), computed in that
  provider's tenant context as the member. `MyToday` asks every provider
  through this port and merges the answers.
  """

  @type item :: %{
          kind: String.t(),
          id: String.t(),
          at: DateTime.t() | nil,
          title: String.t() | nil,
          status: String.t() | nil
        }

  @callback items(
              tenant_context :: map(),
              user_id :: Ecto.UUID.t(),
              date :: Date.t(),
              timezone :: String.t()
            ) :: {:ok, [item()]} | {:error, term()}
end
