defmodule MilosTraining.Nutrition.Ports.NutritionStore do
  @moduledoc "Persistence port of the Nutrition context (ADR-098)."

  @callback get_plan(map(), binary()) :: map() | nil
  @callback put_plan(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_plan(map(), binary()) :: :ok
end
