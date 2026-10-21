defmodule Palee.Application.CreateClassType do
  alias Palee.Scheduling
  alias Palee.Scheduling.Domain.ClassTypeNaming

  def call(context, params), do: Scheduling.create_class_type(context, attrs(params))
  def call(params), do: Scheduling.create_class_type(attrs(params))

  defp attrs(params) do
    name = params[:name] || params["name"]

    %{
      name: name,
      slug: ClassTypeNaming.slugify(name),
      sort_order: params[:sort_order] || params["sort_order"] || 0
    }
    |> put_phase_b(params)
  end

  # ADR-097: credit weighting and event classes; Phase 2 level and audience
  # tags. Omitted values keep defaults.
  @doc false
  def put_phase_b(attrs, params) do
    Enum.reduce([:credit_cost, :kind, :level, :audiences], attrs, fn key, acc ->
      case Map.get(params, key, Map.get(params, Atom.to_string(key))) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end
end
