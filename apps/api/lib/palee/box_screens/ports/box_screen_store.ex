defmodule Palee.BoxScreens.Ports.BoxScreenStore do
  @moduledoc """
  Persistence of box screens (ADR-253). Every callback but
  `find_pairing/2` takes the tenant context first and runs in its scope.

  `find_pairing/2` is the only lookup outside a tenant: an unexpired code's
  hash to `{organization_id, screen_id}` (through the narrow
  `palee_box_screen_pairing` function). `claim/4` then locks the row in the
  box's scope, checks the code again and spends it, so a code pairs one
  device once.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback list(context()) :: [map()]
  @callback count(context()) :: non_neg_integer()
  @callback get(context(), id()) :: map() | nil
  @callback insert(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback update(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete(context(), id()) :: :ok | {:error, :not_found}
  @callback find_pairing(binary(), DateTime.t()) :: {id(), id()} | nil
  @doc "Spends the code: clears it, bumps the token version and marks the screen paired."
  @callback claim(context(), id(), binary(), DateTime.t()) ::
              {:ok, map()} | {:error, :invalid_pairing_code}
  @doc "Records that the screen was seen, at most once a minute."
  @callback touch(context(), id(), DateTime.t()) :: :ok
end
