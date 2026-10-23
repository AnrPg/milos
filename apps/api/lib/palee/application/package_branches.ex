defmodule Palee.Application.PackageBranches do
  @moduledoc """
  The branches of a package (`facility.location_ids`, ADR-097) as a covering
  item of ADR-186 §8: branch staff see the packages valid at their branches,
  and create or change only packages valid inside them.
  """

  alias Palee.Application.CoveringBranches
  alias Palee.Finance

  @field "facility.location_ids"

  @doc "The branches a stored package is valid at."
  def target(%{} = package) do
    fields = Map.get(package, :fields) || %{}
    CoveringBranches.target(Map.get(fields, @field))
  end

  @doc "Params of a new package, with its branches checked or defaulted."
  def for_create(context, params) do
    fields = fields(params)

    with {:ok, target} <- CoveringBranches.for_new(context, Map.get(fields, @field)) do
      if target == :all and not Map.has_key?(fields, @field),
        do: {:ok, params},
        else: {:ok, put_fields(params, Map.put(fields, @field, CoveringBranches.stored(target)))}
    end
  end

  @doc "`:ok` when the acting staff may change package `id` with `params`."
  def authorize_change(context, id, params) do
    case Finance.get_package(context, id) do
      nil ->
        {:error, :not_found}

      package ->
        fields = fields(params)

        with :ok <- CoveringBranches.authorize(context, target(package)) do
          if Map.has_key?(fields, @field),
            do: CoveringBranches.authorize(context, CoveringBranches.target(fields[@field])),
            else: :ok
        end
    end
  end

  @doc "The packages the acting staff see."
  def visible(context, packages), do: CoveringBranches.visible(context, packages, &target/1)

  defp fields(params), do: Map.get(params, :fields) || Map.get(params, "fields") || %{}

  defp put_fields(params, fields) do
    if Map.has_key?(params, "fields") or not Enum.any?(Map.keys(params), &is_atom/1),
      do: Map.put(params, "fields", fields),
      else: Map.put(params, :fields, fields)
  end
end
