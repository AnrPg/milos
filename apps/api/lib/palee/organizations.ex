defmodule Palee.Organizations do
  alias Palee.Organizations.Domain.{
    BrandLogoPolicy,
    Provider,
    TenantAuthorization,
    TimeZonePolicy,
    WorkoutSettingsPolicy
  }

  alias Palee.Organizations.OrganizationStore
  alias Palee.Infrastructure.Tenancy.RepoContext

  alias Palee.Organizations.Commands.{
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

  alias Palee.Organizations.Queries.{
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

  @legacy_organization %{name: "Legacy organization", slug: "legacy-organization"}

  def legacy_organization_slug, do: @legacy_organization.slug
  def legacy_organization_name, do: @legacy_organization.name

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
    to: Palee.Organizations.Queries.ListActiveOrganizationsForSystem,
    as: :call

  defdelegate list_memberships(user_id), to: ListMemberships, as: :call

  @doc """
  ADR-162: everyone who provides the member's training, active and former
  (`Domain.Provider`), read in the member's personal session.
  """
  def list_my_providers(%{user_id: user_id}) when is_binary(user_id) do
    RepoContext.run(%{user_id: user_id}, fn ->
      OrganizationStore.list_my_providers()
      |> Enum.filter(&Provider.provider_row?/1)
      |> Enum.map(&Provider.from_row/1)
    end)
  end

  @doc """
  ADR-185: a person's memberships without their own organiser
  organisation (the one behind «Ως εγώ»), which is never a gym, a provider
  or a club to them: lists of gyms, Box ▾ and the club bar use this.
  """
  def provider_memberships(memberships) when is_list(memberships),
    do: Enum.reject(memberships, &hosting_only?/1)

  @doc "ADR-185: whether a membership entry is of an organiser organisation."
  def hosting_only?(%{organization: %{provider_kind: kind}}), do: kind == "organiser"
  def hosting_only?(_entry), do: false

  @doc "ADR-185: the person's own organiser organisation, or nil."
  def organiser_organization(user_id),
    do: Palee.Organizations.Commands.EnsureOrganiserOrganization.find(user_id)

  @doc """
  ADR-185: the person's organiser organisation, created on first use with
  `opts[:seed_defaults]` inside the creation transaction. Returns
  `{:ok, organization, created?}`.
  """
  def ensure_organiser_organization(account, params, opts \\ []),
    do: Palee.Organizations.Commands.EnsureOrganiserOrganization.call(account, params, opts)

  @doc "ADR-185: archives an organiser organisation that never got an event (the sweep)."
  def archive_empty_organiser(organization_id),
    do: Palee.Organizations.Commands.EnsureOrganiserOrganization.archive_empty(organization_id)

  @doc "ADR-185: the provider kind of each organisation (any session)."
  def provider_kinds(organization_ids), do: OrganizationStore.provider_kinds(organization_ids)

  @doc """
  ADR-162: the coaches of the member's active providers, as
  `{organization_id, coach_user_id}`, read in the member's personal session.
  """
  def list_my_provider_coaches(%{user_id: user_id}) when is_binary(user_id) do
    RepoContext.run(%{user_id: user_id}, &OrganizationStore.list_my_provider_coaches/0)
  end

  @doc "The provider Box ▾ last opened on (may no longer be active)."
  def get_provider_selection(%{user_id: user_id}) when is_binary(user_id),
    do:
      RepoContext.run(%{user_id: user_id}, fn ->
        OrganizationStore.get_provider_selection(user_id)
      end)

  def put_provider_selection(%{user_id: user_id}, organization_id) when is_binary(user_id),
    do:
      RepoContext.run(%{user_id: user_id}, fn ->
        OrganizationStore.put_provider_selection(user_id, organization_id)
      end)

  @doc "Whether the gym presents as a gym or an independent coach (ADR-162)."
  def get_provider_kind(%{organization_id: organization_id} = context)
      when is_binary(organization_id) do
    RepoContext.run(context, fn ->
      kind = OrganizationStore.get_provider_kind(organization_id)
      if kind in Provider.kinds(), do: kind, else: "gym"
    end)
  end

  @doc """
  The owner marks the organization as a gym or an independent coach
  (ADR-162): members see it so in Box ▾, labels and the coach audience.
  """
  def put_provider_kind(%{organization_id: organization_id} = context, kind)
      when is_binary(organization_id) do
    with :ok <- TenantAuthorization.authorize(context, [:owner]),
         :ok <- if(kind in Provider.kinds(), do: :ok, else: {:error, :invalid_provider_kind}) do
      RepoContext.run(context, fn ->
        OrganizationStore.put_provider_kind(organization_id, kind)
      end)
    end
  end

  def put_provider_kind(_context, _kind), do: {:error, :organization_context_required}

  defdelegate split_providers(providers), to: Provider, as: :split
  defdelegate provider_directory(providers), to: Provider, as: :directory
  defdelegate selected_provider(active, remembered_id), to: Provider, as: :selected
  defdelegate active_provider_ids(providers), to: Provider, as: :active_ids

  defdelegate list_active_membership_user_ids(context_or_organization_id),
    to: ListActiveMembershipUserIds,
    as: :call

  def list_membership_organization_ids(user_ids),
    do: OrganizationStore.list_membership_organization_ids(user_ids)

  @doc """
  ADR-176: the IANA zone the gym operates in, read by every gym-local rule:
  the confirmed or inferred zone, else Palee's default while unknown.
  """
  def organization_timezone(organization_id) when is_binary(organization_id),
    do: organization_id |> timezone_status() |> Map.fetch!(:timezone)

  @doc """
  ADR-176: the gym's zone and how it was learnt: `source` is `"confirmed"`,
  `"inferred"` or nil (unknown; `timezone` is then the default).
  """
  def timezone_status(organization_id) when is_binary(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      settings = OrganizationStore.get_organization_settings(organization_id)

      %{
        timezone: TimeZonePolicy.resolve(settings),
        source: settings && settings.timezone_source,
        confirmed: TimeZonePolicy.confirmed?(settings || %{})
      }
    end)
  end

  @doc "ADR-176: the gym's local date now."
  def local_today(organization_id, now \\ DateTime.utc_now()),
    do: local_date(organization_id, now)

  @doc """
  ADR-176: the gym-local day an instant falls on (the day a class at 00:30
  belongs to). Takes a gym id or a tenant context; without a gym, the UTC day.
  """
  def local_date(organization_id, %DateTime{} = at) when is_binary(organization_id),
    do: Palee.TimeZones.ZonedTime.local_date(at, organization_timezone(organization_id))

  def local_date(%{organization_id: organization_id}, %DateTime{} = at)
      when is_binary(organization_id),
      do: local_date(organization_id, at)

  def local_date(_organization_id, %DateTime{} = at), do: DateTime.to_date(at)

  @doc "ADR-179: `timezone_status/1` of several gyms, by id."
  def timezone_statuses(organization_ids) when is_list(organization_ids),
    do: organization_ids |> Enum.uniq() |> Map.new(&{&1, timezone_status(&1)})

  @doc "ADR-176: confirm the gym's zone (`\"confirmed\"`) or report a guess (`\"inferred\"`)."
  defdelegate set_timezone(context, zone, source),
    to: Palee.Organizations.Commands.SetTimeZone,
    as: :call

  @doc "ADR-179: the zone gym-local rules read from a gym's settings (default while unknown)."
  defdelegate resolve_timezone(settings), to: TimeZonePolicy, as: :resolve

  @doc "ADR-179: whether an admin confirmed the zone in a gym's settings."
  def timezone_confirmed?(settings), do: TimeZonePolicy.confirmed?(settings || %{})

  @doc "ADR-176: the best guess among candidate zones (device first, then IP)."
  defdelegate infer_timezone(candidates), to: TimeZonePolicy, as: :infer

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
    to: Palee.Organizations.Domain.TenantAuthorization

  defdelegate staff?(context), to: Palee.Organizations.Domain.TenantAuthorization

  defdelegate roles_in(context),
    to: Palee.Organizations.Domain.TenantAuthorization,
    as: :roles

  defdelegate can?(context, capability),
    to: Palee.Organizations.Domain.TenantAuthorization

  defdelegate capability_scope(context, capability),
    to: Palee.Organizations.Domain.TenantAuthorization,
    as: :scope

  defdelegate authorize_capability(context, capability),
    to: Palee.Organizations.Domain.TenantAuthorization

  @doc "Roles that run a gym: owner and admin (ADR-099)."
  defdelegate admin_roles(), to: Palee.Organizations.Domain.MembershipPolicy

  @doc "Every membership role (ADR-099)."
  defdelegate roles(), to: Palee.Organizations.Domain.MembershipPolicy

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
      |> Palee.Organizations.Domain.AccessPolicy.capabilities(coach_scope: membership.coach_scope)
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

  @doc """
  ADR-209: records that an invitation's token went only into an email, so
  redeeming it proves the inbox and marks the bound address verified.
  Idempotent. Runs in the caller's database scope (a vendor's or a tenant's
  `RepoContext`, or the caller's transaction): `:ok`, or
  `{:error, :not_found}` when the invitation is unknown or out of scope.
  """
  def mark_invitation_emailed(invitation_id, now \\ DateTime.utc_now()),
    do: OrganizationStore.mark_invitation_emailed(invitation_id, now)

  @doc "ADR-209: one invitation of the acting box, for a resend."
  def get_invitation(context, invitation_id),
    do: Palee.Organizations.Queries.EmailedInvitations.get(context, invitation_id)

  @doc "ADR-209: `%{organization:, inviter:}` invitations emailed since `since`."
  def count_emailed_invitations(context, since),
    do: Palee.Organizations.Queries.EmailedInvitations.count_since(context, since)

  @doc """
  Runs `fun` in one database transaction (joining the caller's): `{:ok, value}`
  commits, `{:error, reason}` rolls back. ADR-209 issues an invitation and
  queues its email together.
  """
  def transaction(fun) when is_function(fun, 0), do: OrganizationStore.transaction(fun)

  def revoke_invitation(context, invitation_id, revoked_at \\ DateTime.utc_now()),
    do: RevokeInvitation.call(context, invitation_id, revoked_at)

  def list_active_invitations(context, now \\ DateTime.utc_now()),
    do: Palee.Organizations.Queries.ListActiveInvitations.call(context, now)

  def get_join_link(context), do: Palee.Organizations.Queries.GetJoinLink.call(context)

  def update_join_link(context, params),
    do: Palee.Organizations.Commands.UpdateJoinLink.call(context, params)

  @doc "ADR-163: the gym's workout-authoring defaults (any staff member may read them)."
  def get_workout_settings(context),
    do: Palee.Organizations.Queries.GetWorkoutSettings.call(context)

  @doc "ADR-180: whether the gym lets coaches use the WOD assistant (on by default)."
  def wod_assistant_enabled?(context),
    do: context |> get_workout_settings() |> WorkoutSettingsPolicy.wod_assistant_enabled?()

  def update_workout_settings(context, params),
    do: Palee.Organizations.Commands.UpdateWorkoutSettings.call(context, params)

  def get_onboarding_state(context),
    do: Palee.Organizations.Queries.GetOnboardingState.call(context)

  def update_onboarding(context, params, now \\ DateTime.utc_now()),
    do: Palee.Organizations.Commands.UpdateOnboarding.call(context, params, now)

  @doc "Builds the onboarding checklist view from stored state and setup signals."
  def onboarding_checklist(state, signals, audience \\ "gym"),
    do: Palee.Organizations.Domain.OnboardingChecklist.build(state, signals, audience)

  @doc "ADR-170: which onboarding checklist the context's organization gets (`gym` | `coach`)."
  def onboarding_audience(%{organization: %{provider_kind: kind}}),
    do: Palee.Organizations.Domain.OnboardingChecklist.audience(kind)

  def onboarding_audience(_context), do: "gym"

  def inspect_join_link(slug), do: Palee.Organizations.Queries.InspectJoinLink.call(slug)

  def join_by_link(slug, user_id, joined_at \\ DateTime.utc_now()),
    do:
      slug
      |> Palee.Organizations.Commands.JoinByLink.call(user_id, joined_at)
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
  tenant. The application-level mirror of `palee_acting_user_coaches/1`.
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
        Palee.DomainEvents.publish(:membership_activated, %{
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
      Palee.Organizations.Domain.AccessPolicy.capabilities(roles,
        coach_scope: coach_scope,
        role_grants: role_grants
      )

  @doc """
  An owner creates another gym. Takes the same `:seed_defaults` option as
  `provision_organization/3`; `Application.CreateOwnedOrganization` supplies
  the platform defaults.
  """
  def create_owned_organization(account, params, opts \\ []),
    do: Palee.Organizations.Commands.OwnerOrganizationActions.create(account, params, opts)

  @doc """
  ADR-170: an account opens its own practice as an independent coach (a
  one-person organization of kind `coach`). `opts[:seed_defaults]` as in
  `create_owned_organization/3`.
  """
  def create_coach_practice(account, params, opts \\ []),
    do: Palee.Organizations.Commands.CreateCoachPractice.call(account, params, opts)

  @doc """
  ADR-170: seats the organization uses, keyed like the plan limits:
  `staff_seats` (active owners, admins and staff plus staff invitations not
  yet redeemed) and `active_clients` (active members and athletes without a
  staff role). Owners and admins only.
  """
  def seat_usage(%{organization_id: organization_id} = context, now \\ DateTime.utc_now()) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
      seats =
        RepoContext.run(context, fn -> OrganizationStore.count_seats(organization_id, now) end)

      {:ok,
       %{
         "staff_seats" => seats.staff + seats.pending_staff_invitations,
         "active_clients" => seats.clients
       }}
    end
  end

  @doc "Whether the account already holds an owner, admin or staff role in the context's gym."
  def staff_member?(%{organization_id: organization_id} = context, user_id)
      when is_binary(user_id) do
    RepoContext.run(context, fn ->
      case OrganizationStore.get_membership(organization_id, user_id) do
        %{status: :active, roles: roles} -> Enum.any?(roles, &(&1 in staff_and_admin_roles()))
        _other -> false
      end
    end)
  end

  def staff_member?(_context, _user_id), do: false

  @doc "Roles that take a staff seat (ADR-170)."
  def staff_and_admin_roles,
    do:
      Palee.Organizations.Domain.MembershipPolicy.admin_roles() ++
        Palee.Organizations.Domain.MembershipPolicy.staff_roles()

  def transfer_ownership(context, to_user_id),
    do: Palee.Organizations.Commands.OwnerOrganizationActions.transfer(context, to_user_id)

  def archive_organization(context, confirm),
    do: Palee.Organizations.Commands.OwnerOrganizationActions.archive(context, confirm)

  def get_role_grants(context),
    do: Palee.Organizations.Commands.SetRoleGrants.get(context)

  def set_role_grants(context, role, capabilities),
    do: Palee.Organizations.Commands.SetRoleGrants.call(context, role, capabilities)

  def grantable_capabilities,
    do: Palee.Organizations.Commands.SetRoleGrants.grantable()

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
    do: Palee.Organizations.Domain.PurgePolicy.step_completed?(purge.steps, step)

  def purge_resume_stage(purge),
    do: Palee.Organizations.Domain.PurgePolicy.resume_stage(purge)

  # Organizations' own tenant rows are exported like every other context's;
  # they are purged by `complete_organization_purge/3` (organization delete).
  def tenant_data_policy, do: Palee.Organizations.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def resolve_system_tenant_context(organization_id, source, request_metadata \\ %{})
      when is_binary(organization_id) and is_atom(source) do
    case get_by_id(organization_id) do
      %{status: :active} = organization ->
        {:ok,
         %Palee.Organizations.SystemTenantContext{
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
    do: Palee.Organizations.PublicProfileStore.get(context)

  def upsert_public_profile(context, params),
    do: Palee.Organizations.PublicProfileStore.upsert(context, params)

  def create_tag_suggestion(context, params),
    do: Palee.Organizations.PublicProfileStore.create_suggestion(context, params)

  def pending_tag_suggestions,
    do: Palee.Organizations.PublicProfileStore.pending_suggestions()

  @doc "The published gym a slug or one of its aliases names, for visitors (ADR-142)."
  def public_box_by_slug(slug),
    do: Palee.Organizations.PublicProfileStore.public_box_by_slug(slug)

  @doc "Name, slug, logo and colour of the published gyms among `ids`."
  def public_boxes(ids), do: Palee.Organizations.PublicProfileStore.public_boxes(ids)

  def resolve_tag_suggestion(id, status),
    do: Palee.Organizations.PublicProfileStore.resolve_suggestion(id, status)

  defdelegate box_vocabulary(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :vocabulary

  defdelegate box_amenities(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :amenities

  defdelegate box_services(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :services

  defdelegate box_suggestion_lists(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :suggestion_lists

  defdelegate box_profile_missing(profile),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :missing

  defdelegate box_disciplines(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :disciplines

  defdelegate box_audiences(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :audiences

  defdelegate default_box_languages(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :default_languages

  defdelegate box_profile_max_photos(),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :max_photos

  defdelegate normalize_box_photo_ids(ids),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :normalize_photo_ids

  defdelegate box_profile_publishable?(profile),
    to: Palee.Organizations.Domain.BoxProfilePolicy,
    as: :publishable?

  # -- ADR-186: branch-scoped staff --------------------------------------

  @doc """
  Capabilities of a role set in a gym, narrowed to a branch scope (ADR-186):
  branch-scoped staff lose the capabilities over the whole business.
  """
  def capabilities_for(roles, coach_scope, role_grants, location_scope),
    do:
      roles
      |> capabilities_for(coach_scope, role_grants)
      |> Palee.Organizations.Domain.LocationScopePolicy.narrow_capabilities(location_scope)

  @doc "`:all` or the location ids the acting staff member works at."
  defdelegate location_scope(context),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :scope

  @doc "Whether a location (nil = none) is one the acting staff member works at."
  defdelegate location_in_scope?(context, location_id),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :covers?

  @doc "`:ok` or `{:error, :location_out_of_scope}`."
  defdelegate authorize_location(context, location_id),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :authorize

  @doc "Keeps the located items (`:location_id`, or `location_of`) in the acting scope."
  defdelegate filter_by_location_scope(context, items),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :filter

  defdelegate filter_by_location_scope(context, items, location_of),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :filter

  @doc "Narrows a requested location filter (nil = any) to the acting scope."
  defdelegate restrict_location_filter(context, requested),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :restrict

  @doc "The location a desk action happens at, defaulting to a one-branch scope."
  defdelegate desk_location(context, location_id),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :desk_location

  @doc "Parses a requested scope against the gym's active location ids."
  defdelegate parse_location_scope(params, known_location_ids),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :parse

  defdelegate location_scope_requested?(params),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :requested?

  defdelegate location_scope_payload(scope),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :to_payload

  @doc "The branches a report shows: requested ones inside the scope (ADR-186 §7)."
  defdelegate report_filter(context, requested_ids),
    to: Palee.Organizations.Domain.LocationScopePolicy

  @doc "The `location_ids` a request names (list or comma-separated)."
  defdelegate requested_location_ids(params),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :requested_ids

  @doc "The branches a one-place item is created at, one item each (ADR-186 §8)."
  defdelegate location_creation_targets(context, requested_ids, single_location_id),
    to: Palee.Organizations.Domain.LocationScopePolicy,
    as: :creation_targets

  @doc "Whether an item valid at `target` (`:all` or ids) shows for a scope or filter."
  defdelegate covering_visible?(scope_or_filter, target),
    to: Palee.Organizations.Domain.LocationScopePolicy

  @doc "`:ok` when an item valid at `target` lies inside the acting scope (ADR-186 §8)."
  defdelegate authorize_covering(context, target),
    to: Palee.Organizations.Domain.LocationScopePolicy

  @doc "Sets the branches someone works at (`:all` or parsed ids)."
  def set_membership_location_scope(context, user_id, scope),
    do: Palee.Organizations.Commands.SetMembershipLocationScope.call(context, user_id, scope)

  @doc """
  The effective scopes of a gym's memberships, `%{membership_id => scope}`,
  for directory and profile payloads. Memberships missing from `memberships`
  work everywhere.
  """
  def membership_location_scopes(context, memberships) do
    scoped = Enum.filter(memberships, &(Map.get(&1, :all_locations) == false))

    ids =
      Palee.Organizations.LocationScopeStore.location_ids_by_membership(
        context,
        Enum.map(scoped, & &1.id)
      )

    Map.new(memberships, fn membership ->
      {membership.id,
       Palee.Organizations.Domain.LocationScopePolicy.effective(
         membership.roles || [membership.role],
         Map.get(membership, :all_locations, true),
         Map.get(ids, membership.id, [])
       )}
    end)
  end

  @doc """
  The scope stored on one membership of the context's gym, whatever its roles
  (`:all` or active location ids; nil when there is no membership), for the
  editor in Admin › Χρήστες.
  """
  def stored_location_scope(context, user_id) when is_binary(user_id) do
    RepoContext.run(context, fn ->
      case OrganizationStore.get_membership(context.organization_id, user_id) do
        %{} = membership ->
          Palee.Organizations.Commands.SetMembershipLocationScope.stored_scope(
            context,
            membership
          )

        _missing ->
          nil
      end
    end)
  end

  def stored_location_scope(_context, _user_id), do: nil

  # ADR-184: business accounts stay in demo mode until the platform team
  # activates them. `GoLivePolicy` is the one gate; these are its entry points.

  @doc """
  `:ok` when the organization (or the context's) may take a going-live
  action, else `{:error, :business_not_activated}` (see `GoLivePolicy`).
  """
  def go_live(organization_or_context, action, facts \\ %{}),
    do:
      Palee.Organizations.Domain.GoLivePolicy.check(
        gated_subject(organization_or_context),
        action,
        facts
      )

  @doc "Whether the organization is a gym or coach business still in demo mode."
  def business_gated?(organization_or_context),
    do: Palee.Organizations.Domain.GoLivePolicy.gated?(gated_subject(organization_or_context))

  @doc "`%{activation, gated}` for session payloads."
  def business_status(organization_or_context),
    do: Palee.Organizations.Domain.GoLivePolicy.status(gated_subject(organization_or_context))

  defdelegate gated_business_kinds(),
    to: Palee.Organizations.Domain.GoLivePolicy,
    as: :gated_kinds

  @doc """
  ADR-184: an account opens a business of `kind` (gym | coach) in demo mode.
  `opts[:seed_defaults]` as in `create_owned_organization/3`.
  """
  def create_business_account(account, kind, params, opts \\ []),
    do: Palee.Organizations.Commands.CreateBusinessAccount.call(account, kind, params, opts)

  @doc """
  ADR-184: a mock person's membership in a demo business. Unlike
  `add_membership/1` it announces nothing (`:membership_activated` would
  start referral, trial and event reactions for someone who does not exist).
  """
  def add_demo_membership(%{organization_id: organization_id, user_id: user_id}, params)
      when is_binary(organization_id) and is_binary(user_id) do
    RepoContext.run(%{organization_id: organization_id, user_id: user_id}, fn ->
      params |> Map.put(:organization_id, organization_id) |> AddMembership.call()
    end)
  end

  @doc """
  ADR-184: on activation the account the link names holds `roles` in the
  business (added to the roles it already has). Runs as that account: a
  person may write their own membership row.
  """
  def grant_activation_roles(organization_id, user_id, roles, now)
      when is_binary(organization_id) and is_binary(user_id) and is_list(roles) do
    RepoContext.run(%{organization_id: organization_id, user_id: user_id}, fn ->
      existing = OrganizationStore.get_membership(organization_id, user_id)
      held = if existing && existing.status == :active, do: existing.roles, else: []
      wanted = held ++ roles
      ordered = Enum.filter(Palee.Organizations.Domain.MembershipPolicy.roles(), &(&1 in wanted))

      OrganizationStore.add_membership(%{
        organization_id: organization_id,
        user_id: user_id,
        role: Palee.Organizations.Domain.MembershipPolicy.primary_role(ordered),
        roles: ordered,
        coach_scope: if(:coach in ordered, do: :all, else: :own),
        status: :active,
        joined_at: (existing && existing.joined_at) || now
      })
    end)
  end

  defp gated_subject(%{organization: %{} = organization}), do: organization
  defp gated_subject(organization), do: organization

  defp legacy_membership_role(:admin), do: :owner
  defp legacy_membership_role(:athlete), do: :athlete
  defp legacy_membership_role(_role), do: :member
end
