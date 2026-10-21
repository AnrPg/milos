defmodule Palee.Organizations.Commands.IssueInvitation do
  alias Palee.Organizations.Domain.{
    InvitationToken,
    MembershipPolicy,
    TenantAuthorization
  }

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.InvitationEmail
  alias Palee.Organizations.OrganizationStore

  @default_lifetime_seconds 604_800

  def call(context, params, issued_at) do
    with :ok <- TenantAuthorization.authorize_capability(context, :invite_clients),
         role <- normalize_role(value(params, :role)),
         :ok <- authorize_role_ceiling(TenantAuthorization.roles(context), role) do
      token = InvitationToken.generate()
      lifetime = value(params, :lifetime_seconds) || @default_lifetime_seconds

      invitation_params = %{
        organization_id: context.organization_id,
        token_digest: InvitationToken.digest(token),
        role: role,
        expires_at: DateTime.add(issued_at, lifetime, :second),
        issued_by_user_id: context.user_id,
        coach_user_id: invited_coach(context, role, params),
        intended_email_digest: InvitationEmail.digest(value(params, :intended_email))
      }

      # registration_invitations is a root tenant table (TD-046).
      case RepoContext.run(context, fn ->
             OrganizationStore.issue_invitation(invitation_params, issued_at)
           end) do
        {:ok, invitation} -> {:ok, %{invitation: invitation, token: token}}
        error -> error
      end
    end
  end

  # Owners invite anyone, admins staff and clients, coaches and front desk
  # only clients (ADR-099).
  defp authorize_role_ceiling(issuer_roles, target_role) do
    if MembershipPolicy.can_grant_role?(issuer_roles, target_role) do
      :ok
    else
      {:error, :role_ceiling_exceeded}
    end
  end

  # A coach inviting a client becomes that client's coach (ADR-100); a coach
  # who also manages the gym chooses with `as_my_client`.
  defp invited_coach(context, role, params) do
    roles = TenantAuthorization.roles(context)
    manager? = Enum.any?(roles, &(&1 in [:owner, :admin]))
    as_my_client = value(params, :as_my_client)

    if :coach in roles and role in MembershipPolicy.client_roles() and
         (as_my_client in [true, "true"] or
            (not manager? and as_my_client not in [false, "false"])),
       do: context.user_id
  end

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    Enum.find(MembershipPolicy.roles(), role, &(Atom.to_string(&1) == role))
  end

  defp normalize_role(role), do: role
  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
