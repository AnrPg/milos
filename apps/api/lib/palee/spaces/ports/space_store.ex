defmodule Palee.Spaces.Ports.SpaceStore do
  @moduledoc "Persistence port for spaces, floor plans and unavailability (ADR-202), room photos and cleaning points (ADR-290)."

  @callback list_spaces(map(), map()) :: [map()]
  @callback get_space(map(), binary()) :: map() | nil
  @callback save_space(map(), binary() | nil, map()) :: {:ok, map()} | {:error, term()}
  @callback list_floor_plans(map(), map()) :: [map()]
  @callback get_floor_plan(map(), binary()) :: map() | nil
  @callback save_floor_plan(map(), binary() | nil, map()) :: {:ok, map()} | {:error, term()}
  @callback delete_floor_plan(map(), binary()) :: {:ok, map()} | {:error, term()}
  @callback list_unavailabilities(map(), [binary()], DateTime.t()) :: [map()]
  @callback create_unavailability(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_unavailability(map(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  # ADR-290: the gym's choices, room photos and cleaning points.
  @callback get_settings(map()) :: map()
  @callback put_settings(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_photos(map(), :photos | :points, map()) :: [map()]
  @callback get_photo(map(), :photos | :points, binary()) :: map() | nil
  @callback save_photo(map(), :photos | :points, binary() | nil, map()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_photo(map(), :photos | :points, binary()) :: {:ok, map()} | {:error, term()}
  @callback order_photos(map(), :photos | :points, [{binary(), non_neg_integer()}]) :: :ok
end
