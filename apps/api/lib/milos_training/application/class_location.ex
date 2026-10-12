defmodule MilosTraining.Application.ClassLocation do
  @moduledoc "Checks the optional Facility location of a class or series (ADR-097)."

  alias MilosTraining.Facility
  alias MilosTraining.Facility.Domain.CheckInPolicy

  @doc "`:ok` when params name no location or an active one of the organization."
  def check(context, params) when is_map(params) do
    case Map.get(params, :location_id) || Map.get(params, "location_id") do
      id when id in [nil, ""] ->
        :ok

      id ->
        case Facility.get_location(context, id) do
          nil -> {:error, :location_not_found}
          location -> CheckInPolicy.usable_location(location)
        end
    end
  end
end
