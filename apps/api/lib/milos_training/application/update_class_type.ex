defmodule MilosTraining.Application.UpdateClassType do
  alias MilosTraining.Scheduling

  def call(context, id, params) do
    Scheduling.update_class_type(context, id, %{
      name: params[:name] || params["name"],
      sort_order: params[:sort_order] || params["sort_order"] || 0
    })
  end

  def call(id, params) do
    Scheduling.update_class_type(id, %{
      name: params[:name] || params["name"],
      sort_order: params[:sort_order] || params["sort_order"] || 0
    })
  end
end
