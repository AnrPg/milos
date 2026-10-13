defmodule MilosTraining.Application.CreateClassType do
  alias MilosTraining.Scheduling
  alias MilosTraining.Scheduling.Domain.ClassTypeNaming

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

  # ADR-097: credit weighting and event classes; omitted values keep defaults.
  @doc false
  def put_phase_b(attrs, params) do
    Enum.reduce([:credit_cost, :kind], attrs, fn key, acc ->
      case Map.get(params, key, Map.get(params, Atom.to_string(key))) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end
end
