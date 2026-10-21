defmodule Palee.Application.ListOrganizationInvitations do
  alias Palee.Organizations

  def call(context), do: Organizations.list_active_invitations(context)
end
