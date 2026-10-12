defmodule MilosTraining.Organizations.Commands.RevokeInvitation do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.TenantAuthorization
  alias MilosTraining.Organizations.OrganizationStore

  # registration_invitations is a root tenant table: RLS admits the row only in
  # the acting owner/admin's tenant scope (TD-046).
  def call(context, invitation_id, revoked_at) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
      RepoContext.run(context, fn ->
        OrganizationStore.revoke_invitation(context.organization_id, invitation_id, revoked_at)
      end)
    end
  end
end
