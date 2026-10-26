defmodule Palee.Spaces.Ports.SpaceStore do
  @moduledoc "Persistence port for spaces, floor plans and unavailability (ADR-202)."

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
end
