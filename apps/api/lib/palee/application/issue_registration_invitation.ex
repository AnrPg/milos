defmodule Palee.Application.IssueRegistrationInvitation do
  @moduledoc "A gym invites someone; a staff invitation reserves a staff seat of the plan (ADR-170)."

  alias Palee.Application.OrganizationPlan
  alias Palee.Organizations

  def call(context, params) do
    role = Map.get(params, :role, Map.get(params, "role"))

    with :ok <- OrganizationPlan.check_invitation(context, role) do
      Organizations.issue_invitation(context, params)
    end
  end
end
