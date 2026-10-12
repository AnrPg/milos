defmodule MilosTraining.Organizations do
  alias MilosTraining.Organizations.Domain.{BrandLogoPolicy, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore

  alias MilosTraining.Organizations.Commands.{
    AddMembership,
    AdvanceOrganizationPurge,
    CompleteOrganizationPurge,
    CreateOrganization,
    DeleteOrganization,
    IssueInvitation,
    IssuePlatformInvitation,
    ProvisionOrganization,
    RedeemInvitation,
    RenameOrganization,
    RenameOrganizationSlug,
    ReplaceOrganizationLogo,
    RequestOrganizationPurge,
    RevokeInvitation,
    SendOwnerInvitationEmail,
    SetMembershipRole,
    SetMembershipStatus,
    UpdateOrganizationLifecycle,
    UpdateMembershipRole,
    UpdateOrganizationSettings
  }

  alias MilosTraining.Organizations.Queries.{
    BuildTenantPurgeContext,
    FindOrganization,
    GetOrganizationBranding,
    GetOrganizationPurge,
    GetSlugRenameImpact,
    InspectInvitation,
    ListActiveMembershipUserIds,
    ListDeletableOrganizationUserIds,
    ListMemberships,
    ListOrganizationMemberships,
    ListProvisionedOrganizations,
    ListStaffUserIds,
    ResolvePlatformContext,
    ResolveSlugAlias,
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

  defdelegate list_active_membership_user_ids(context_or_organization_id),
    to: ListActiveMembershipUserIds,
    as: :call

  def list_membership_organization_ids(user_ids),
    do: OrganizationStore.list_membership_organization_ids(user_ids)

  defdelegate list_staff_user_ids(organization_id), to: ListStaffUserIds, as: :call

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

  @doc """
  ADR-129: whether the tenant context's acting member is a coach of the
  tenant. The application-level mirror of `milos_acting_user_coaches/1`.
  """
  def acting_user_coaches?(context), do: TenantAuthorization.coaches?(context)

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

  # ADR-122 slug rename with retired-slug aliases.
  def rename_organization_slug(
        context,
        organization_id,
        params,
        changed_at \\ DateTime.utc_now()
      ),
      do: RenameOrganizationSlug.call(context, organization_id, params, changed_at)

  def slug_rename_impact(context, organization_id, now \\ DateTime.utc_now()),
    do: GetSlugRenameImpact.call(context, organization_id, now)

  def resolve_slug_alias(slug), do: ResolveSlugAlias.call(slug)

  def send_owner_invitation_email(context, organization_id, params),
    do: SendOwnerInvitationEmail.call(context, organization_id, params)

  def update_organization_settings(
        context,
        organization_id,
        params,
        changed_at \\ DateTime.utc_now()
      ),
      do: UpdateOrganizationSettings.call(context, organization_id, params, changed_at)

  # ADR-121 first-class tenant logo upload. `context` is a tenant owner/admin
  # `TenantContext` (organization_id may be nil: their own organization) or a
  # vendor `PlatformContext` (organization_id required).
  def get_organization_branding(context, organization_id \\ nil),
    do: GetOrganizationBranding.call(context, organization_id)

  def authorize_logo_change(context, organization_id \\ nil),
    do: BrandLogoPolicy.authorize(context, organization_id)

  @doc "Validates an upload request and allocates the object key it may write."
  def allocate_logo_key(organization_id, content_type, byte_size) do
    with {:ok, content_type} <- BrandLogoPolicy.validate_request(content_type, byte_size) do
      {:ok,
       %{
         key: BrandLogoPolicy.object_key(organization_id, Ecto.UUID.generate(), content_type),
         content_type: content_type,
         max_bytes: BrandLogoPolicy.max_bytes()
       }}
    end
  end

  def logo_key_owned?(organization_id, key), do: BrandLogoPolicy.owned_key?(organization_id, key)
  def logo_probe_bytes, do: BrandLogoPolicy.probe_bytes()
  def validate_logo_object(key, object), do: BrandLogoPolicy.validate_object(key, object)

  def superseded_logo_key(organization_id, previous_key, next_key),
    do: BrandLogoPolicy.superseded_key(organization_id, previous_key, next_key)

  def set_organization_logo(context, organization_id, logo, changed_at \\ DateTime.utc_now()),
    do: ReplaceOrganizationLogo.call(context, organization_id, logo, changed_at)

  def remove_organization_logo(context, organization_id, changed_at \\ DateTime.utc_now()),
    do: ReplaceOrganizationLogo.call(context, organization_id, nil, changed_at)

  # ADR-117 reviewed tenant export/purge workflow. Purge records are
  # platform-level and survive the organization they describe.
  def request_organization_purge(context, organization_id, requested_at \\ DateTime.utc_now()),
    do: RequestOrganizationPurge.call(context, organization_id, requested_at)

  def advance_organization_purge(
        context,
        purge_id,
        event,
        attrs \\ %{},
        at \\ DateTime.utc_now()
      ),
      do: AdvanceOrganizationPurge.call(context, purge_id, event, attrs, at)

  def record_organization_purge_step(context, purge_id, step, result, at \\ DateTime.utc_now()),
    do: AdvanceOrganizationPurge.call(context, purge_id, {:record_step, step, result}, %{}, at)

  def approve_organization_purge(
        context,
        organization_id,
        confirmation,
        at \\ DateTime.utc_now()
      ),
      do: AdvanceOrganizationPurge.approve(context, organization_id, confirmation, at)

  def cancel_organization_purge(context, organization_id, at \\ DateTime.utc_now()),
    do: AdvanceOrganizationPurge.cancel(context, organization_id, at)

  def complete_organization_purge(context, purge_id, completed_at \\ DateTime.utc_now()),
    do: CompleteOrganizationPurge.call(context, purge_id, completed_at)

  def get_organization_purge(context, organization_id),
    do: GetOrganizationPurge.latest(context, organization_id)

  def get_organization_purge_by_id(context, purge_id),
    do: GetOrganizationPurge.by_id(context, purge_id)

  def list_organization_purges(context), do: GetOrganizationPurge.list(context)

  def tenant_purge_context(context, purge), do: BuildTenantPurgeContext.call(context, purge)

  def purge_step_completed?(purge, step),
    do: MilosTraining.Organizations.Domain.PurgePolicy.step_completed?(purge.steps, step)

  def purge_resume_stage(purge),
    do: MilosTraining.Organizations.Domain.PurgePolicy.resume_stage(purge)

  # Organizations' own tenant rows are exported like every other context's;
  # they are purged by `complete_organization_purge/3` (organization delete).
  def tenant_data_policy, do: MilosTraining.Organizations.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

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
