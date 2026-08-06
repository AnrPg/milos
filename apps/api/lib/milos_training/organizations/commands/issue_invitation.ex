defmodule MilosTraining.Organizations.Commands.IssueInvitation do
  alias MilosTraining.Organizations.Domain.{
    InvitationToken,
    MembershipPolicy,
    TenantAuthorization
  }

  alias MilosTraining.Organizations.Domain.InvitationEmail
  alias MilosTraining.Organizations.OrganizationStore

  @default_lifetime_seconds 604_800

  def call(context, params, issued_at) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]),
         role <- normalize_role(value(params, :role)),
         :ok <- authorize_role_ceiling(context.role, role) do
      token = InvitationToken.generate()
      lifetime = value(params, :lifetime_seconds) || @default_lifetime_seconds

      invitation_params = %{
        organization_id: context.organization_id,
        token_digest: InvitationToken.digest(token),
        role: role,
        expires_at: DateTime.add(issued_at, lifetime, :second),
        issued_by_user_id: context.user_id,
        intended_email_digest: InvitationEmail.digest(value(params, :intended_email))
      }

      case OrganizationStore.issue_invitation(invitation_params, issued_at) do
        {:ok, invitation} -> {:ok, %{invitation: invitation, token: token}}
        error -> error
      end
    end
  end

  defp authorize_role_ceiling(issuer_role, target_role) do
    if MembershipPolicy.can_grant_role?(issuer_role, target_role) do
      :ok
    else
      {:error, :role_ceiling_exceeded}
    end
  end


  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    Enum.find(MembershipPolicy.roles(), role, &(Atom.to_string(&1) == role))
  end

  defp normalize_role(role), do: role
  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
