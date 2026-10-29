defmodule Palee.Organizations.Domain.AccessPolicy do
  @moduledoc """
  What each membership role may do, and over which data (ADR-099). The
  specification is `docs/architecture/rights-per-account-type.md`.

  A capability's scope is `:all` (every client and record of the gym), `:own`
  (a coach's own clients and classes, ADR-100) or `:status` (membership status
  only). Rights are the union of the roles; the wider scope wins.
  """

  @scope_rank %{status: 0, own: 1, all: 2}

  @admin %{
    grant_staff_roles: :all,
    set_head_coach: :all,
    manage_memberships: :all,
    invite_clients: :all,
    manage_settings: :all,
    # ADR-186: a branch's own settings (address, hours, door codes); a branch
    # manager keeps it for their branches while gym-wide settings stay with
    # staff who work everywhere.
    manage_locations: :all,
    view_directory: :all,
    view_billing_contacts: :all,
    view_client_training: :all,
    view_health: :all,
    # ADR-252: clients' health certificates (dates and files, GDPR art. 9).
    manage_health_certificates: :all,
    view_feedback: :all,
    manage_packages: :all,
    view_package_catalog: :all,
    view_membership_status: :all,
    take_payments: :all,
    manage_billing: :all,
    manage_promotions: :all,
    view_promotions: :all,
    # ADR-191: partner perks (create, publish, pause, export claims).
    manage_perks: :all,
    view_finance_reports: :all,
    manage_finance_settings: :all,
    manage_schedule: :all,
    run_classes: :all,
    check_in: :all,
    manage_workouts: :all,
    assign_coaches: :all,
    manage_coaching: :all,
    manage_appointments: :all,
    book_for_clients: :all,
    read_coach_notes: :all,
    manage_content: :all,
    manage_challenges: :all,
    message_clients: :all,
    message_from_box: :all,
    broadcast: :all,
    view_business_analytics: :all,
    view_coaching_analytics: :all,
    record_cleaning: :all,
    review_cleaning: :all,
    manage_cleaning_areas: :all,
    # ADR-202: spaces (rooms) of each branch, and when they are cleaned.
    manage_spaces: :all,
    edit_space_details: :all,
    set_space_unavailable: :all,
    view_spaces: :all,
    manage_cleaning_schedule: :all,
    manage_inventory: :all,
    manage_shop: :all,
    sell_shop: :all,
    moderate_community: :all,
    manage_community: :all,
    manage_events: :all
  }

  @owner Map.merge(@admin, %{
           create_organization: :all,
           manage_organization_lifecycle: :all,
           manage_platform_subscription: :all,
           grant_admin_roles: :all
         })

  # Coaching rights a head coach holds over every client (ADR-100).
  @coaching_scoped [
    :view_directory,
    :view_client_training,
    :view_health,
    :view_feedback,
    :view_membership_status,
    :run_classes,
    :check_in,
    :manage_coaching,
    :manage_appointments,
    :message_clients,
    :broadcast,
    :view_coaching_analytics
  ]

  @coach Map.merge(Map.new(@coaching_scoped, &{&1, :own}), %{
           invite_clients: :all,
           view_package_catalog: :all,
           manage_workouts: :all,
           self_assign_athletes: :all,
           write_coach_notes: :own,
           manage_content: :all,
           manage_challenges: :all,
           report_inventory: :all,
           view_spaces: :all,
           moderate_community: :all,
           manage_events: :all
         })

  @front_desk %{
    invite_clients: :all,
    view_directory: :all,
    view_package_catalog: :all,
    view_membership_status: :all,
    take_payments: :all,
    run_classes: :all,
    check_in: :all,
    book_for_clients: :all,
    message_clients: :all,
    message_from_box: :all,
    review_cleaning: :all,
    manage_cleaning_schedule: :all,
    view_spaces: :all,
    edit_space_details: :all,
    set_space_unavailable: :all,
    manage_inventory: :all,
    sell_shop: :all
  }

  @accountant %{
    view_billing_contacts: :all,
    manage_packages: :all,
    view_package_catalog: :all,
    view_membership_status: :all,
    take_payments: :all,
    manage_billing: :all,
    view_promotions: :all,
    view_finance_reports: :all,
    manage_finance_settings: :all,
    message_from_box: :all
  }

  @janitor %{record_cleaning: :own, report_inventory: :all}

  @grants %{
    owner: @owner,
    admin: @admin,
    coach: @coach,
    front_desk: @front_desk,
    accountant: @accountant,
    janitor: @janitor,
    member: %{},
    athlete: %{}
  }

  # What a gym may unlock for a role on top of its defaults (ADR-099,
  # docs/architecture/navigation-by-role.md §3).
  @grantable %{
    front_desk: [
      :manage_billing,
      :manage_promotions,
      :manage_packages,
      :view_finance_reports,
      :manage_shop,
      # ADR-202: adding and archiving spaces and drawing floor plans.
      :manage_spaces,
      # ADR-252: the desk collecting clients' health certificates.
      :manage_health_certificates
    ]
  }

  def grantable, do: @grantable

  @doc """
  The capabilities of a role set as `%{capability => scope}`. Options:
  `coach_scope: :all` makes a coach a head coach; `role_grants` (a gym's
  `%{"front_desk" => ["manage_billing", ...]}`) adds unlocked capabilities.
  """
  def capabilities(roles, opts \\ []) do
    head_coach? = Keyword.get(opts, :coach_scope) in [:all, "all"]
    role_grants = Keyword.get(opts, :role_grants) || %{}

    roles
    |> List.wrap()
    |> Enum.map(&Map.merge(grants_for(&1, head_coach?), unlocked(&1, role_grants)))
    |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _capability, a, b -> wider(a, b) end))
  end

  def can?(capabilities, capability), do: Map.has_key?(capabilities, capability)
  def scope(capabilities, capability), do: Map.get(capabilities, capability)

  @doc "Every capability any role can hold."
  def all_capabilities, do: (Map.keys(@owner) ++ Map.keys(@coach)) |> Enum.uniq()

  @doc "Parses a gym's grants for a role, keeping only grantable capabilities."
  def unlocked(role, role_grants) do
    allowed = Map.get(@grantable, role, [])

    role_grants
    |> Map.get(to_string(role), Map.get(role_grants, role, []))
    |> List.wrap()
    |> Enum.map(&to_capability(&1, allowed))
    |> Enum.reject(&is_nil/1)
    |> Map.new(&{&1, :all})
  end

  defp to_capability(capability, allowed) when is_atom(capability),
    do: if(capability in allowed, do: capability)

  defp to_capability(capability, allowed) when is_binary(capability),
    do: Enum.find(allowed, &(Atom.to_string(&1) == capability))

  defp to_capability(_capability, _allowed), do: nil

  defp grants_for(:coach, true), do: Map.merge(@coach, Map.new(@coaching_scoped, &{&1, :all}))
  defp grants_for(role, _head_coach?), do: Map.get(@grants, role, %{})

  defp wider(a, b), do: if(@scope_rank[a] >= @scope_rank[b], do: a, else: b)
end
