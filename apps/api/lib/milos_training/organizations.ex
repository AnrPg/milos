defmodule MilosTraining.Organizations do
  alias MilosTraining.Organizations.Domain.{BrandLogoPolicy, TenantAuthorization}
  alias MilosTraining.Organizations.OrganizationStore
  alias MilosTraining.Infrastructure.Tenancy.RepoContext

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
    SetCoachScope,
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
    ListMemberRoles,
    ListStaffUserIds,
    ResolvePlatformContext,
    ResolveSlugAlias,
    ResolveTenantContext
  }

  @legacy_organization %{name: "Milos Training", slug: "legacy-milos-training"}

  def legacy_organization_slug, do: @legacy_organization.slug

  defdelegate create_organization(params), to: CreateOrganization, as: :call
  def add_membership(params), do: params |> AddMembership.call() |> announce_activation()
  defdelegate get_by_id(id), to: FindOrganization, as: :by_id
  defdelegate get_by_slug(slug), to: FindOrganization, as: :by_slug
  defdelegate get_by_domain(host), to: FindOrganization, as: :by_domain
  defdelegate get_organization_settings(id), to: FindOrganization, as: :settings_by_id

  @doc """
  TD-092 / ADR-131: the active organizations a per-tenant cron job visits, as
  `%{organization: organization, settings: settings}`. Works without any
  session scope (an Oban job); each row is read inside its own organization's
  scope.
  """
  defdelegate list_active_organizations_for_system(),
    to: MilosTraining.Organizations.Queries.ListActiveOrganizationsForSystem,
    as: :call

  defdelegate list_memberships(user_id), to: ListMemberships, as: :call

  defdelegate list_active_membership_user_ids(context_or_organization_id),
    to: ListActiveMembershipUserIds,
    as: :call

  def list_membership_organization_ids(user_ids),
    do: OrganizationStore.list_membership_organization_ids(user_ids)

  @doc "IANA timezone the organization operates in (defaults to UTC)."
  def organization_timezone(organization_id) when is_binary(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      case OrganizationStore.get_organization_settings(organization_id) do
        %{timezone: timezone} when is_binary(timezone) and timezone != "" -> timezone
        _missing -> "Etc/UTC"
      end
    end)
  end

  @doc """
  ADR-155: how a box presents itself on a Wallet card - its name (the brand
  name when set), slug, logo URL and primary colour. Nil for an unknown box.
  """
  def brand_summary(organization_id) when is_binary(organization_id) do
    with %{} = organization <- get_by_id(organization_id) do
      settings =
        RepoContext.run(%{organization_id: organization_id}, fn ->
          OrganizationStore.get_organization_settings(organization_id)
        end) || %{}

      brand_name =
        case Map.get(settings, :brand_name) do
          name when is_binary(name) ->
            if String.trim(name) == "", do: nil, else: String.trim(name)

          _none ->
            nil
        end

      %{
        organization_id: organization.id,
        name: brand_name || organization.name,
        slug: organization.slug,
        logo_url: Map.get(settings, :brand_logo_url),
        primary_color: Map.get(settings, :brand_primary_color)
      }
    end
  end

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
    case member(organization_id, user_id) do
      %{roles: roles} -> roles
      nil -> []
    end
  end

  def member_roles(_organization_id, _user_id), do: []

  @doc """
  Where a person stands with a gym (ADR-144): `:member` (active), `:former`
  (suspended or revoked), or `:none` (never joined, or only invited).
  """
  def membership_standing(organization_id, user_id)
      when is_binary(organization_id) and is_binary(user_id) do
    # The person's own scope: the membership policies let anyone read their
    # own membership row, whoever is asking.
    RepoContext.run(%{organization_id: organization_id, user_id: user_id}, fn ->
      case OrganizationStore.get_membership(organization_id, user_id) do
        %{status: :active} -> :member
        %{status: status} when status in [:suspended, :revoked] -> :former
        _none -> :none
      end
    end)
  end

  @doc "A member's roles and coach scope in the gym, or nil (ADR-099, ADR-100)."
  def membership_summary(organization_id, user_id) do
    case member(organization_id, user_id) do
      %{} = membership ->
        %{
          roles: Enum.map(membership.roles, &to_string/1),
          coach_scope: to_string(membership.coach_scope || :own),
          home_location_id: membership.home_location_id
        }

      nil ->
        nil
    end
  end

  @doc """
  Sets the location a member's gym opens on (Phase 2). Callers decide who may
  set it; the database keeps the location inside the same gym.
  """
  def put_home_location(context, user_id, location_id) do
    RepoContext.run(context, fn ->
      case OrganizationStore.get_membership(context.organization_id, user_id) do
        nil ->
          {:error, :not_found}

        membership ->
          OrganizationStore.update_membership_settings(
            context.organization_id,
            membership.id,
            %{home_location_id: location_id}
          )
      end
    end)
  end

  @doc "Whether a coach lets admins read their private notes (ADR-101)."
  def notes_visible_to_admins?(organization_id, user_id) do
    case member(organization_id, user_id) do
      %{notes_visible_to_admins: visible} -> visible != false
      nil -> true
    end
  end

  @doc "A coach sets whether admins may read their private notes (ADR-101)."
  def set_notes_visibility(context, visible) when is_boolean(visible) do
    with :ok <- authorize_capability(context, :write_coach_notes) do
      RepoContext.run(context, fn ->
        OrganizationStore.update_membership_settings(
          context.organization_id,
          context.membership_id,
          %{notes_visible_to_admins: visible}
        )
      end)
    end
  end

  def set_notes_visibility(_context, _visible), do: {:error, [visible: "must be true or false"]}

  @doc "Active owners and admins of a gym (ADR-099)."
  def list_manager_user_ids(organization_id) do
    organization_id
    |> ListMemberRoles.call(roles: [:owner, :admin])
    |> Enum.map(& &1.user_id)
  end

  @doc "Active members whose roles carry `capability` (role defaults, ADR-099)."
  def list_user_ids_with_capability(organization_id, capability) do
    organization_id
    |> ListMemberRoles.call()
    |> Enum.filter(fn membership ->
      membership.roles
      |> MilosTraining.Organizations.Domain.AccessPolicy.capabilities(
        coach_scope: membership.coach_scope
      )
      |> Map.has_key?(capability)
    end)
    |> Enum.map(& &1.user_id)
  end

  defdelegate list_staff_user_ids(organization_id), to: ListStaffUserIds, as: :call

  @doc """
  Active owners, admins and coaches of a gym, with their primary role and
  role set there (coach pickers, ADR-098/099).
  """
  def list_staff(organization_id) do
    organization_id
    |> ListMemberRoles.call(roles: [:owner, :admin, :coach])
    |> Enum.map(&Map.take(&1, [:user_id, :role, :roles]))
  end

  defp member(organization_id, user_id) do
    organization_id
    |> ListMemberRoles.call(user_id: user_id)
    |> List.first()
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

  def list_active_invitations(context, now \\ DateTime.utc_now()),
    do: MilosTraining.Organizations.Queries.ListActiveInvitations.call(context, now)

  def get_join_link(context), do: MilosTraining.Organizations.Queries.GetJoinLink.call(context)

  def update_join_link(context, params),
    do: MilosTraining.Organizations.Commands.UpdateJoinLink.call(context, params)

  def get_onboarding_state(context),
    do: MilosTraining.Organizations.Queries.GetOnboardingState.call(context)

  def update_onboarding(context, params, now \\ DateTime.utc_now()),
    do: MilosTraining.Organizations.Commands.UpdateOnboarding.call(context, params, now)

  @doc "Builds the onboarding checklist view from stored state and setup signals."
  def onboarding_checklist(state, signals),
    do: MilosTraining.Organizations.Domain.OnboardingChecklist.build(state, signals)

  def inspect_join_link(slug), do: MilosTraining.Organizations.Queries.InspectJoinLink.call(slug)

  def join_by_link(slug, user_id, joined_at \\ DateTime.utc_now()),
    do:
      slug
      |> MilosTraining.Organizations.Commands.JoinByLink.call(user_id, joined_at)
      |> announce_activation()

  def inspect_invitation(token, now \\ DateTime.utc_now()),
    do: InspectInvitation.call(token, now)

  def redeem_invitation(token, user_id, redeemed_at \\ DateTime.utc_now()),
    do: token |> RedeemInvitation.call(user_id, redeemed_at) |> announce_activation()

  def resolve_tenant_context(account, slug, request_metadata \\ %{}),
    do: ResolveTenantContext.call(account, slug, request_metadata)

  def resolve_tenant_context_by_id(account, organization_id, request_metadata \\ %{}),
    do: ResolveTenantContext.by_id(account, organization_id, request_metadata)

  @doc """
  ADR-129: whether the tenant context's acting member is a coach of the
  tenant. The application-level mirror of `milos_acting_user_coaches/1`.
  """
  def acting_user_coaches?(context), do: TenantAuthorization.coaches?(context)

  def resolve_platform_context(account, request_metadata \\ %{}),
    do: ResolvePlatformContext.call(account, request_metadata)

  def grant_vendor(user_id), do: OrganizationStore.grant_vendor(user_id)

  def revoke_vendor(user_id), do: OrganizationStore.revoke_vendor(user_id)

  @doc """
  Vendor provisioning. `opts`: `:issued_at`, and `:seed_defaults` - a
  `(%{organization_id, user_id} -> {:ok, term} | {:error, term})` that writes
  another context's defaults in the new tenant's scope, in the same
  transaction (ADR-133). `Application.ProvisionOrganization` supplies the
  platform defaults.
  """
  def provision_organization(context, params, opts \\ []),
    do: ProvisionOrganization.call(context, params, opts)

  def list_provisioned_organizations(context),
    do: ListProvisionedOrganizations.call(context)

  def list_organization_memberships(context, organization_id),
    do: ListOrganizationMemberships.call(context, organization_id)

  def list_deletable_organization_user_ids(context, organization_id),
    do: ListDeletableOrganizationUserIds.call(context, organization_id)

  def update_membership_role(context, organization_id, membership_id, params),
    do: UpdateMembershipRole.call(context, organization_id, membership_id, params)

  def set_membership_status(context, membership_id, status),
    do: context |> SetMembershipStatus.call(membership_id, status) |> announce_activation()

  # ADR-144: every way a person becomes an active member announces it, so
  # other contexts (trials conversion, later referrals) can react.
  defp announce_activation({:ok, result} = outcome) do
    case activated_membership(result) do
      %{organization_id: organization_id, user_id: user_id} ->
        MilosTraining.DomainEvents.publish(:membership_activated, %{
          organization_id: organization_id,
          user_id: user_id,
          at: DateTime.utc_now()
        })

      nil ->
        :ok
    end

    outcome
  end

  defp announce_activation(outcome), do: outcome

  defp activated_membership(%{created: false}), do: nil
  defp activated_membership(%{membership: membership}), do: activated_membership(membership)

  defp activated_membership(%{status: :active, organization_id: org, user_id: user} = membership)
       when is_binary(org) and is_binary(user),
       do: membership

  defp activated_membership(_result), do: nil

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

  @doc """
  An owner creates another gym. Takes the same `:seed_defaults` option as
  `provision_organization/3`; `Application.CreateOwnedOrganization` supplies
  the platform defaults.
  """
  def create_owned_organization(account, params, opts \\ []),
    do:
      MilosTraining.Organizations.Commands.OwnerOrganizationActions.create(account, params, opts)

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

  # Public profile of a gym (ADR-142).
  def get_public_profile(context),
    do: MilosTraining.Organizations.PublicProfileStore.get(context)

  def upsert_public_profile(context, params),
    do: MilosTraining.Organizations.PublicProfileStore.upsert(context, params)

  def create_tag_suggestion(context, params),
    do: MilosTraining.Organizations.PublicProfileStore.create_suggestion(context, params)

  def pending_tag_suggestions,
    do: MilosTraining.Organizations.PublicProfileStore.pending_suggestions()

  @doc "The published gym a slug or one of its aliases names, for visitors (ADR-142)."
  def public_box_by_slug(slug),
    do: MilosTraining.Organizations.PublicProfileStore.public_box_by_slug(slug)

  @doc "Name, slug, logo and colour of the published gyms among `ids`."
  def public_boxes(ids), do: MilosTraining.Organizations.PublicProfileStore.public_boxes(ids)

  def resolve_tag_suggestion(id, status),
    do: MilosTraining.Organizations.PublicProfileStore.resolve_suggestion(id, status)

  defdelegate box_vocabulary(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :vocabulary

  defdelegate box_amenities(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :amenities

  defdelegate box_services(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :services

  defdelegate box_suggestion_lists(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :suggestion_lists

  defdelegate box_profile_missing(profile),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :missing

  defdelegate box_disciplines(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :disciplines

  defdelegate box_audiences(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :audiences

  defdelegate default_box_languages(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :default_languages

  defdelegate box_profile_max_photos(),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :max_photos

  defdelegate normalize_box_photo_ids(ids),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :normalize_photo_ids

  defdelegate box_profile_publishable?(profile),
    to: MilosTraining.Organizations.Domain.BoxProfilePolicy,
    as: :publishable?

  defp legacy_membership_role(:admin), do: :owner
  defp legacy_membership_role(:athlete), do: :athlete
  defp legacy_membership_role(_role), do: :member
end
