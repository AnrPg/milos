defmodule MilosTraining.Execution.Commands.Params do
  @moduledoc false

  def get(params, key) when is_atom(key),
    do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  def uuid(params, key) do
    case get(params, key) do
      value when is_binary(value) ->
        case Ecto.UUID.cast(value) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, :bad_request}
        end

      _other ->
        {:error, :bad_request}
    end
  end

  def positive_integer(params, key) do
    case get(params, key) do
      value when is_integer(value) and value >= 1 -> {:ok, value}
      _other -> {:error, :bad_request}
    end
  end
end
