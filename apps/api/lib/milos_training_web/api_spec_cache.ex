defmodule MilosTrainingWeb.ApiSpecCache do
  @moduledoc """
  OpenApiSpex cache that stores the spec in `:persistent_term` once.

  The default cache re-puts the whole spec the first time each controller
  action is validated, and every put copies the spec into the VM's literal
  area. With a large spec that exhausts the area during warm-up. This cache
  precomputes the operation of every routed controller action, so the lookup
  is complete on the first put and later puts with no new keys are skipped.
  """

  @behaviour OpenApiSpex.Plug.Cache

  @impl true
  def get(spec_module), do: :persistent_term.get(key(spec_module), nil)

  @impl true
  def put(spec_module, {spec, lookup}) do
    lookup = Map.merge(controller_actions(lookup), lookup)

    case get(spec_module) do
      {_spec, stored} when map_size(stored) >= map_size(lookup) -> :ok
      _missing_or_smaller -> :persistent_term.put(key(spec_module), {spec, lookup})
    end
  end

  @impl true
  def erase(spec_module) do
    :persistent_term.erase(key(spec_module))
    :ok
  end

  defp key(spec_module), do: {__MODULE__, spec_module}

  defp controller_actions(lookup) do
    MilosTrainingWeb.Router.__routes__()
    |> Enum.flat_map(fn %{plug: controller, plug_opts: action} ->
      with true <- is_atom(action),
           true <- function_exported?(controller, :open_api_operation, 1),
           %{operationId: operation_id} <- controller.open_api_operation(action),
           %{} = operation <- Map.get(lookup, operation_id) do
        [{{controller, action}, operation}]
      else
        _not_documented -> []
      end
    end)
    |> Map.new()
  end
end
