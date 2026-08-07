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
    RevokeInvitation,
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
  defdelegate list_active_membership_user_ids(context), to: ListActiveMembershipUserIds, as: :call

  def list_membership_organization_ids(user_ids),
    do: OrganizationStore.list_membership_organization_ids(user_ids)

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

  def update_membership_role(context, organization_id, membership_id, params),
    do: UpdateMembershipRole.call(context, organization_id, membership_id, params)

  def set_membership_status(context, membership_id, status),
    do: SetMembershipStatus.call(context, membership_id, status)

  def set_membership_role(context, user_id, role),
    do: SetMembershipRole.call(context, user_id, role)

  def delete_organization(context, organization_id, deleted_at \\ DateTime.utc_now()),
    do: DeleteOrganization.call(context, organization_id, deleted_at)

  def update_organization_lifecycle(
        context,
        organization_id,
        status,
        changed_at \\ DateTime.utc_now()
      ),
      do: UpdateOrganizationLifecycle.call(context, organization_id, status, changed_at)

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

  def ensure_legacy_organization do
    case get_by_slug(@legacy_organization.slug) do
      nil -> create_legacy_organization()
      organization -> {:ok, organization}
    end
  end

  def ensure_legacy_membership(account, role \\ nil) do
    with {:ok, organization} <- ensure_legacy_organization() do
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
