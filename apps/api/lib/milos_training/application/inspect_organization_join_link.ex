defmodule MilosTraining.Application.InspectOrganizationJoinLink do
  alias MilosTraining.Organizations

  def call(slug), do: Organizations.inspect_join_link(slug)
end
