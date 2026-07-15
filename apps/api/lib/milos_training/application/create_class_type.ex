defmodule MilosTraining.Application.CreateClassType do
  alias MilosTraining.Scheduling
  alias MilosTraining.Scheduling.Domain.ClassTypeNaming

  def call(params) do
    name = params[:name] || params["name"]
    sort_order = params[:sort_order] || params["sort_order"] || 0

    Scheduling.create_class_type(%{
      name: name,
      slug: ClassTypeNaming.slugify(name),
      sort_order: sort_order
    })
  end
end
