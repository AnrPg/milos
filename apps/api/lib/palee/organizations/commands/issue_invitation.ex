defmodule Palee.Organizations.Commands.IssueInvitation do
  alias Palee.Organizations.Domain.{
    GoLivePolicy,
    InvitationToken,
    LocationScopePolicy,
    MembershipPolicy,
    TenantAuthorization
  }

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.InvitationEmail
  alias Palee.Organizations.OrganizationStore

  @default_lifetime_seconds 604_800

  @doc """
  Issues a one-time link. `params` carry `role` (one role, older clients) or
  `roles` (a role set, ADR-186), and `location_scope` (`:all` or location ids
  already checked against the gym's locations by the caller) for staff
  invitations; without one, a staff invitation gets the issuer's own scope.
  """
  def call(context, params, issued_at) do
    with :ok <- TenantAuthorization.authorize_capability(context, :invite_clients),
         # ADR-184: a business in demo mode invites nobody real.
         :ok <- GoLivePolicy.check(Map.get(context, :organization), :invite_people),
         {:ok, roles} <- requested_roles(params),
         :ok <- authorize_role_ceiling(TenantAuthorization.roles(context), roles),
         {:ok, scope} <- invitation_scope(context, roles, params) do
      token = InvitationToken.generate()
      lifetime = value(params, :lifetime_seconds) || @default_lifetime_seconds

      invitation_params = %{
        organization_id: context.organization_id,
        token_digest: InvitationToken.digest(token),
        role: MembershipPolicy.primary_role(roles),
        roles: roles,
        all_locations: scope == :all,
        location_ids: if(scope == :all, do: [], else: scope),
        expires_at: DateTime.add(issued_at, lifetime, :second),
        issued_by_user_id: context.user_id,
        coach_user_id: invited_coach(context, roles, params),
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

  # ADR-186: `roles` (a set) wins over the single `role` older clients send.
  defp requested_roles(params) do
    case value(params, :roles) do
      [_ | _] = roles -> MembershipPolicy.normalize_roles(roles)
      _single -> {:ok, [normalize_role(value(params, :role))]}
    end
  end

  # Owners invite anyone, admins staff and clients, coaches and front desk
  # only clients (ADR-099), for every role of the set.
  defp authorize_role_ceiling(issuer_roles, target_roles) do
    if Enum.all?(target_roles, &MembershipPolicy.can_grant_role?(issuer_roles, &1)) do
      :ok
    else
      {:error, :role_ceiling_exceeded}
    end
  end

  # ADR-186: clients and owners work everywhere; staff get the requested
  # branches, never more than the issuer's own, and the issuer's own scope
  # when none is requested.
  defp invitation_scope(context, roles, params) do
    issuer_scope = LocationScopePolicy.scope(context)

    scope =
      case Map.get(params, :location_scope) do
        nil -> issuer_scope
        requested -> requested
      end

    cond do
      :owner in roles or not LocationScopePolicy.staff?(roles) ->
        {:ok, :all}

      scope != :all and not is_list(scope) ->
        {:error, :invalid_location_scope}

      true ->
        with :ok <- LocationScopePolicy.authorize_grant(issuer_scope, scope), do: {:ok, scope}
    end
  end

  # A coach inviting a client becomes that client's coach (ADR-100); a coach
  # who also manages the gym chooses with `as_my_client`.
  defp invited_coach(context, invited_roles, params) do
    roles = TenantAuthorization.roles(context)
    manager? = Enum.any?(roles, &(&1 in [:owner, :admin]))
    as_my_client = value(params, :as_my_client)

    if :coach in roles and Enum.all?(invited_roles, &(&1 in MembershipPolicy.client_roles())) and
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
