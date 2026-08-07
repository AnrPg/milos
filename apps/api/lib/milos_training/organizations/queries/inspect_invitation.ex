defmodule MilosTraining.Organizations.Queries.InspectInvitation do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.{InvitationPolicy, InvitationToken}
  alias MilosTraining.Organizations.OrganizationStore

  def call(token, now) do
    # The holder of an invitation is by definition not yet a member, so the
    # membership-based policies cannot apply here (F-16).
    with {:ok, digest} <- InvitationToken.decode(token),
         %{invitation: invitation, organization: organization} <-
           RepoContext.run(%{invitation_redemption: true}, fn ->
             OrganizationStore.get_invitation_with_organization(digest)
           end),
         true <- InvitationPolicy.redeemable?(invitation, now),
         :active <- organization.status do
      {:ok,
       %{
         invitation_id: invitation.id,
         organization: organization,
         role: invitation.role,
         expires_at: invitation.expires_at
       }}
    else
      _reason -> {:error, :invalid_invitation}
    end
  end
end
