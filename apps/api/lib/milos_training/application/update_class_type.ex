defmodule MilosTraining.Application.UpdateClassType do
  alias MilosTraining.Application.CreateClassType
  alias MilosTraining.Scheduling

  def call(context, id, params), do: Scheduling.update_class_type(context, id, attrs(params))
  def call(id, params), do: Scheduling.update_class_type(id, attrs(params))

  defp attrs(params) do
    CreateClassType.put_phase_b(
      %{
        name: params[:name] || params["name"],
        sort_order: params[:sort_order] || params["sort_order"] || 0
      },
      params
    )
  end
end
