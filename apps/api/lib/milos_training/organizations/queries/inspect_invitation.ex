defmodule MilosTraining.Organizations.Queries.InspectInvitation do
  alias MilosTraining.Organizations.Domain.{InvitationPolicy, InvitationToken}
  alias MilosTraining.Organizations.OrganizationStore

  def call(token, now) do
    with {:ok, digest} <- InvitationToken.decode(token),
         %{invitation: invitation, organization: organization} <-
           OrganizationStore.get_invitation_with_organization(digest),
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
