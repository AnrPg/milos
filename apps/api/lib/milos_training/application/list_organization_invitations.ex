defmodule MilosTraining.Application.ListOrganizationInvitations do
  alias MilosTraining.Organizations

  def call(context), do: Organizations.list_active_invitations(context)
end
