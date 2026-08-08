defmodule MilosTrainingWeb.ParamExtractor do
  @moduledoc false

  def body(conn, params) do
    case conn.body_params do
      %{} = body_params when map_size(body_params) > 0 -> body_params
      _ -> get(params, "body") || params
    end
  end

  def get(params, key) when is_binary(key) do
    atom_value =
      try do
        Map.get(params, String.to_existing_atom(key))
      rescue
        ArgumentError -> nil
      end

    Map.get(params, key) || atom_value
  end

  def fetch(params, key) do
    case get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value when not is_nil(value) -> {:ok, value}
      _missing -> {:error, :bad_request}
    end
  end
end
