defmodule PaleeWeb.OpenApiSpecCache do
  @moduledoc """
  Stores the OpenAPI spec in `:persistent_term` once and never overwrites it.

  OpenApiSpex's default `PersistentTermCache` re-stores the whole spec (about
  19 MB) the first time each validated controller action is hit, to memoize
  that action's operation. Every `:persistent_term.put/2` copies the value
  into the VM's literal area and old copies are only freed lazily, so with
  ~50 validated actions the literal area (about 1 GB) runs out and the VM
  aborts (`literal_alloc: Cannot allocate …`). Skipping those re-puts only
  costs a map lookup by operation id per request.
  """
  @behaviour OpenApiSpex.Plug.Cache

  @impl true
  def get(spec_module), do: :persistent_term.get(key(spec_module), nil)

  @impl true
  def put(spec_module, spec_and_lookup) do
    if get(spec_module) == nil, do: :persistent_term.put(key(spec_module), spec_and_lookup)
    :ok
  end

  @impl true
  def erase(spec_module) do
    :persistent_term.erase(key(spec_module))
    :ok
  end

  defp key(spec_module), do: {__MODULE__, spec_module}
end
