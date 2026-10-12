defmodule MilosTraining.Organizations do
  alias MilosTraining.Organizations.OrganizationStore

  alias MilosTraining.Organizations.Commands.{
    AddMembership,
    CreateOrganization,
    DeleteOrganization,
    IssueInvitation,
    IssuePlatformInvitation,
    ProvisionOrganization,
    RedeemInvitation,
    RenameOrganization,
    RevokeInvitation,
    SendOwnerInvitationEmail,
    SetCoachScope,
    SetMembershipRole,
    SetMembershipStatus,
    UpdateOrganizationLifecycle,
    UpdateMembershipRole,
    UpdateOrganizationSettings
  }

  alias MilosTraining.Organizations.Queries.{
    FindOrganization,
    InspectInvitation,
    ListActiveMembershipUserIds,
    ListDeletableOrganizationUserIds,
    ListMemberships,
    ListOrganizationMemberships,
    ListProvisionedOrganizations,
    ResolvePlatformContext,
    ResolveTenantContext
  }

  @legacy_organization %{name: "Milos Training", slug: "legacy-milos-training"}

  def legacy_organization_slug, do: @legacy_organization.slug

  defdelegate create_organization(params), to: CreateOrganization, as: :call
  defdelegate add_membership(params), to: AddMembership, as: :call
  defdelegate get_by_id(id), to: FindOrganization, as: :by_id
  defdelegate get_by_slug(slug), to: FindOrganization, as: :by_slug
  defdelegate get_by_domain(host), to: FindOrganization, as: :by_domain
  defdelegate list_memberships(user_id), to: ListMemberships, as: :call

  def list_active_membership_user_ids(organization_id) when is_binary(organization_id),
    do: OrganizationStore.list_active_membership_user_ids(organization_id)

  def list_active_membership_user_ids(context), do: ListActiveMembershipUserIds.call(context)

  def list_membership_organization_ids(user_ids),
    do: OrganizationStore.list_membership_organization_ids(user_ids)

  @doc "Whether the tenant context holds any of `roles` (ADR-099)."
  defdelegate any_role?(context, roles),
    to: MilosTraining.Organizations.Domain.TenantAuthorization

  defdelegate staff?(context), to: MilosTraining.Organizations.Domain.TenantAuthorization

  defdelegate roles_in(context),
    to: MilosTraining.Organizations.Domain.TenantAuthorization,
    as: :roles

  defdelegate can?(context, capability),
    to: MilosTraining.Organizations.Domain.TenantAuthorization

  defdelegate capability_scope(context, capability),
    to: MilosTraining.Organizations.Domain.TenantAuthorization,
    as: :scope

  defdelegate authorize_capability(context, capability),
    to: MilosTraining.Organizations.Domain.TenantAuthorization

  @doc "Roles that run a gym: owner and admin (ADR-099)."
  defdelegate admin_roles(), to: MilosTraining.Organizations.Domain.MembershipPolicy

  @doc "Every membership role (ADR-099)."
  defdelegate roles(), to: MilosTraining.Organizations.Domain.MembershipPolicy

  @doc "Roles of an active member of the gym, or [] (ADR-099)."
  def member_roles(organization_id, user_id) when is_binary(user_id) do
    case OrganizationStore.get_membership(organization_id, user_id) do
      %{status: :active, roles: roles} -> roles
      _none -> []
    end
  end

  def member_roles(_organization_id, _user_id), do: []

  @doc "A member's roles and coach scope in the gym, or nil (ADR-099, ADR-100)."
  def membership_summary(organization_id, user_id) do
    case OrganizationStore.get_membership(organization_id, user_id) do
      %{status: :active} = membership ->
        %{
          roles: Enum.map(membership.roles, &to_string/1),
          coach_scope: to_string(membership.coach_scope || :own)
        }

      _none ->
        nil
    end
  end

  @doc "Whether a coach lets admins read their private notes (ADR-101)."
  def notes_visible_to_admins?(organization_id, user_id) do
    case OrganizationStore.get_membership(organization_id, user_id) do
      %{notes_visible_to_admins: visible} -> visible != false
      _none -> true
    end
  end

  @doc "A coach sets whether admins may read their private notes (ADR-101)."
  def set_notes_visibility(context, visible) when is_boolean(visible) do
    with :ok <- authorize_capability(context, :write_coach_notes) do
      OrganizationStore.update_membership_settings(
        context.organization_id,
        context.membership_id,
        %{notes_visible_to_admins: visible}
      )
    end
  end

  def set_notes_visibility(_context, _visible), do: {:error, [visible: "must be true or false"]}

  @doc "Active owners and admins of a gym (ADR-099)."
  def list_manager_user_ids(organization_id) do
    organization_id
    |> OrganizationStore.list_organization_memberships()
    |> Enum.filter(
      &(&1.status == :active and Enum.any?(&1.roles, fn r -> r in [:owner, :admin] end))
    )
    |> Enum.map(& &1.user_id)
  end

  @doc "Active members whose roles carry `capability` (role defaults, ADR-099)."
  def list_user_ids_with_capability(organization_id, capability) do
    organization_id
    |> OrganizationStore.list_organization_memberships()
    |> Enum.filter(fn membership ->
      membership.status == :active and
        membership.roles
        |> MilosTraining.Organizations.Domain.AccessPolicy.capabilities(
          coach_scope: membership.coach_scope
        )
        |> Map.has_key?(capability)
    end)
    |> Enum.map(& &1.user_id)
  end

  def list_staff_user_ids(organization_id),
    do: OrganizationStore.list_staff_user_ids(organization_id)

  @doc """
  Active owners, admins and coaches of a gym, with their primary role and
  role set there (coach pickers, ADR-098/099).
  """
  def list_staff(organization_id) do
    staff_roles = [:owner, :admin, :coach]

    organization_id
    |> OrganizationStore.list_organization_memberships()
    |> Enum.filter(
      &(&1.status == :active and Enum.any?(&1.roles, fn role -> role in staff_roles end))
    )
    |> Enum.map(&%{user_id: &1.user_id, role: &1.role, roles: &1.roles})
  end

  def issue_invitation(context, params, issued_at \\ DateTime.utc_now()),
    do: IssueInvitation.call(context, params, issued_at)

  def issue_platform_invitation(
        context,
        organization_id,
        params,
        issued_at \\ DateTime.utc_now()
      ),
      do: IssuePlatformInvitation.call(context, organization_id, params, issued_at)

  def revoke_invitation(context, invitation_id, revoked_at \\ DateTime.utc_now()),
    do: RevokeInvitation.call(context, invitation_id, revoked_at)

  def inspect_invitation(token, now \\ DateTime.utc_now()),
    do: InspectInvitation.call(token, now)

  def redeem_invitation(token, user_id, redeemed_at \\ DateTime.utc_now()),
    do: RedeemInvitation.call(token, user_id, redeemed_at)

  def resolve_tenant_context(account, slug, request_metadata \\ %{}),
    do: ResolveTenantContext.call(account, slug, request_metadata)

  def resolve_platform_context(account, request_metadata \\ %{}),
    do: ResolvePlatformContext.call(account, request_metadata)

  def grant_vendor(user_id), do: OrganizationStore.grant_vendor(user_id)

  def revoke_vendor(user_id), do: OrganizationStore.revoke_vendor(user_id)

  def provision_organization(context, params, issued_at \\ DateTime.utc_now()),
    do: ProvisionOrganization.call(context, params, issued_at)

  def list_provisioned_organizations(context),
    do: ListProvisionedOrganizations.call(context)

  def list_organization_memberships(context, organization_id),
    do: ListOrganizationMemberships.call(context, organization_id)

  def list_deletable_organization_user_ids(context, organization_id),
    do: ListDeletableOrganizationUserIds.call(context, organization_id)

  def update_membership_role(context, organization_id, membership_id, params),
    do: UpdateMembershipRole.call(context, organization_id, membership_id, params)

  def set_membership_status(context, membership_id, status),
    do: SetMembershipStatus.call(context, membership_id, status)

  def set_membership_role(context, user_id, role),
    do: SetMembershipRole.call(context, user_id, role)

  def set_membership_roles(context, user_id, roles),
    do: SetMembershipRole.set_roles(context, user_id, roles)

  def set_coach_scope(context, user_id, scope), do: SetCoachScope.call(context, user_id, scope)

  @doc "Capabilities of a role set in a gym (ADR-099), for session payloads."
  def capabilities_for(roles, coach_scope, role_grants),
    do:
      MilosTraining.Organizations.Domain.AccessPolicy.capabilities(roles,
        coach_scope: coach_scope,
        role_grants: role_grants
      )

  def create_owned_organization(account, params),
    do: MilosTraining.Organizations.Commands.OwnerOrganizationActions.create(account, params)

  def transfer_ownership(context, to_user_id),
    do:
      MilosTraining.Organizations.Commands.OwnerOrganizationActions.transfer(context, to_user_id)

  def archive_organization(context, confirm),
    do: MilosTraining.Organizations.Commands.OwnerOrganizationActions.archive(context, confirm)

  def get_role_grants(context),
    do: MilosTraining.Organizations.Commands.SetRoleGrants.get(context)

  def set_role_grants(context, role, capabilities),
    do: MilosTraining.Organizations.Commands.SetRoleGrants.call(context, role, capabilities)

  def grantable_capabilities,
    do: MilosTraining.Organizations.Commands.SetRoleGrants.grantable()

  def delete_organization(context, organization_id, deleted_at \\ DateTime.utc_now()),
    do: DeleteOrganization.call(context, organization_id, deleted_at)

  def update_organization_lifecycle(
        context,
        organization_id,
        status,
        changed_at \\ DateTime.utc_now()
      ),
      do: UpdateOrganizationLifecycle.call(context, organization_id, status, changed_at)

  def rename_organization(context, organization_id, name),
    do: RenameOrganization.call(context, organization_id, name)

  def send_owner_invitation_email(context, organization_id, params),
    do: SendOwnerInvitationEmail.call(context, organization_id, params)

  def update_organization_settings(
        context,
        organization_id,
        params,
        changed_at \\ DateTime.utc_now()
      ),
      do: UpdateOrganizationSettings.call(context, organization_id, params, changed_at)

  def resolve_system_tenant_context(organization_id, source, request_metadata \\ %{})
      when is_binary(organization_id) and is_atom(source) do
    case get_by_id(organization_id) do
      %{status: :active} = organization ->
        {:ok,
         %MilosTraining.Organizations.SystemTenantContext{
           organization: organization,
           organization_id: organization.id,
           source: source,
           request_metadata: request_metadata || %{}
         }}

      _organization ->
        {:error, :organization_not_found}
    end
  end

  def ensure_legacy_organization,
    do: {:error, :legacy_organization_migration_tool_required}

  def ensure_legacy_membership(_account, _role \\ nil),
    do: {:error, :legacy_organization_migration_tool_required}

  def ensure_legacy_organization_for_migration do
    case get_by_slug(@legacy_organization.slug) do
      nil -> create_legacy_organization()
      organization -> {:ok, organization}
    end
  end

  def ensure_legacy_membership_for_migration(account, role \\ nil) do
    with {:ok, organization} <- ensure_legacy_organization_for_migration() do
      add_membership(%{
        organization_id: organization.id,
        user_id: account.id,
        role: role || legacy_membership_role(account.role),
        status: :active,
        joined_at: DateTime.utc_now()
      })
    end
  end

  defp create_legacy_organization do
    case create_organization(@legacy_organization) do
      {:ok, organization} ->
        {:ok, organization}

      {:error, reason} ->
        case get_by_slug(@legacy_organization.slug) do
          nil -> {:error, reason}
          organization -> {:ok, organization}
        end
    end
  end

  defp legacy_membership_role(:admin), do: :owner
  defp legacy_membership_role(:athlete), do: :athlete
  defp legacy_membership_role(_role), do: :member
end
