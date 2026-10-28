defmodule Palee.Organizations.Queries.InspectInvitation do
  alias Palee.Infrastructure.Tenancy.RepoContext

  alias Palee.Organizations.Domain.{
    GoLivePolicy,
    InvitationPolicy,
    InvitationToken,
    LocationScopePolicy
  }

  alias Palee.Organizations.{OrganizationStore, RegistrationInvitation}

  def call(token, now) do
    # The holder of an invitation is by definition not yet a member, so the
    # membership-based policies cannot apply here (F-16).
    with {:ok, digest} <- InvitationToken.decode(token),
         %{invitation: invitation, organization: organization} <-
           RepoContext.run(%{invitation_redemption: true}, fn ->
             OrganizationStore.get_invitation_with_organization(digest)
           end),
         :active <- organization.status,
         # ADR-184: nobody joins a business still in demo mode.
         :ok <- GoLivePolicy.check(organization, :join),
         :ok <- redeemable(invitation, now) do
      {:ok,
       %{
         invitation_id: invitation.id,
         organization: organization,
         role: invitation.role,
         roles: RegistrationInvitation.granted_roles(invitation),
         location_scope:
           invitation
           |> RegistrationInvitation.granted_scope()
           |> LocationScopePolicy.to_payload(),
         expires_at: invitation.expires_at,
         # ADR-209: the page says it is for one address, never which.
         email_bound: not is_nil(invitation.intended_email_digest)
       }}
    else
      {:error, :invitation_revoked} = revoked -> revoked
      _reason -> {:error, :invalid_invitation}
    end
  end

  # ADR-209: the holder of a revoked invitation's link (the emailed one) is
  # told the box revoked it; the token proves they were sent it.
  defp redeemable(invitation, now) do
    case InvitationPolicy.state(invitation, now) do
      :active -> :ok
      :revoked -> {:error, :invitation_revoked}
      _other -> {:error, :invalid_invitation}
    end
  end
end
