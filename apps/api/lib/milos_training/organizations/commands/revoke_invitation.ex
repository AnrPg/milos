defmodule MilosTraining.Organizations.Commands.RevokeInvitation do
  alias MilosTraining.Organizations.Domain.{MembershipPolicy, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore

  def call(context, invitation_id, revoked_at) do
    with :ok <- TenantAuthorization.authorize(context, MembershipPolicy.admin_roles()) do
      OrganizationStore.revoke_invitation(context.organization_id, invitation_id, revoked_at)
    end
  end
end
