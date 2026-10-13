defmodule MilosTraining.Application.ManageOrganizationJoinLink do
  @moduledoc "Admin use case: read or change the organization's public join link."

  alias MilosTraining.Organizations

  def get(context), do: Organizations.get_join_link(context)
  def update(context, params), do: Organizations.update_join_link(context, params)
end
