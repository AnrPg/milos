defmodule Palee.Application.ChangeMembershipRoles do
  @moduledoc """
  An owner or admin changes what someone is in the gym (ADR-099). A new
  staff holder takes a staff seat of the plan (ADR-170).
  """

  alias Palee.Application.{GoLive, OrganizationPlan}
  alias Palee.Organizations

  @doc "Replaces the target's roles with one role."
  def set_role(context, user_id, role) do
    with :ok <- GoLive.check_role_grant(context, user_id, [role]),
         :ok <- OrganizationPlan.check_role_change(context, user_id, [role]) do
      Organizations.set_membership_role(context, user_id, role)
    end
  end

  @doc "Sets every role the target holds."
  def set_roles(context, user_id, roles) do
    with :ok <- GoLive.check_role_grant(context, user_id, roles),
         :ok <- OrganizationPlan.check_role_change(context, user_id, roles) do
      Organizations.set_membership_roles(context, user_id, roles)
    end
  end
end
