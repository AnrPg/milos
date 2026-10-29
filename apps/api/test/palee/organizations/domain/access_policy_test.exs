defmodule Palee.Organizations.Domain.AccessPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.{AccessPolicy, MembershipPolicy}

  # docs/architecture/rights-per-account-type.md is the specification.
  defp caps(roles, opts \\ []), do: AccessPolicy.capabilities(roles, opts)

  test "owners alone act across gyms and grant owner or admin" do
    for capability <- [
          :create_organization,
          :manage_organization_lifecycle,
          :manage_platform_subscription,
          :grant_admin_roles
        ] do
      assert AccessPolicy.can?(caps([:owner]), capability)
      refute AccessPolicy.can?(caps([:admin]), capability)
    end

    assert AccessPolicy.can?(caps([:admin]), :grant_staff_roles)
    assert AccessPolicy.can?(caps([:admin]), :manage_settings)
  end

  test "an owner has every right an admin has" do
    for {capability, _scope} <- caps([:admin]) do
      assert AccessPolicy.scope(caps([:owner]), capability) == :all, inspect(capability)
    end
  end

  test "coaches coach their own clients and see only membership status" do
    coach = caps([:coach])

    assert AccessPolicy.scope(coach, :manage_coaching) == :own
    assert AccessPolicy.scope(coach, :view_directory) == :own
    assert AccessPolicy.scope(coach, :view_health) == :own
    assert AccessPolicy.scope(coach, :run_classes) == :own
    assert AccessPolicy.scope(coach, :view_membership_status) == :own
    assert AccessPolicy.scope(coach, :manage_workouts) == :all
    assert AccessPolicy.can?(coach, :self_assign_athletes)
    assert AccessPolicy.can?(coach, :invite_clients)

    for capability <- [:manage_billing, :take_payments, :manage_settings, :grant_staff_roles] do
      refute AccessPolicy.can?(coach, capability), inspect(capability)
    end
  end

  test "a head coach coaches every client but gains nothing outside coaching" do
    head = caps([:coach], coach_scope: :all)

    assert AccessPolicy.scope(head, :manage_coaching) == :all
    assert AccessPolicy.scope(head, :view_directory) == :all
    refute AccessPolicy.can?(head, :manage_billing)
    refute AccessPolicy.can?(head, :manage_schedule)
  end

  test "front desk, accountant and janitor stay in their lanes" do
    desk = caps([:front_desk])
    assert AccessPolicy.can?(desk, :check_in)
    assert AccessPolicy.can?(desk, :take_payments)
    assert AccessPolicy.scope(desk, :view_membership_status) == :all
    refute AccessPolicy.can?(desk, :manage_billing)
    refute AccessPolicy.can?(desk, :view_health)

    books = caps([:accountant])
    assert AccessPolicy.can?(books, :manage_billing)
    assert AccessPolicy.can?(books, :view_finance_reports)
    refute AccessPolicy.can?(books, :view_client_training)
    refute AccessPolicy.can?(books, :view_health)

    janitor = caps([:janitor])
    assert AccessPolicy.can?(janitor, :record_cleaning)
    assert Map.keys(janitor) |> Enum.sort() == [:record_cleaning, :report_inventory]
  end

  test "spaces: owners and admins manage, front desk edits details and unavailability (ADR-202)" do
    for role <- [:owner, :admin] do
      rights = caps([role])

      for capability <- [
            :manage_spaces,
            :edit_space_details,
            :set_space_unavailable,
            :view_spaces,
            :manage_cleaning_schedule
          ] do
        assert AccessPolicy.can?(rights, capability), inspect({role, capability})
      end
    end

    desk = caps([:front_desk])
    assert AccessPolicy.can?(desk, :edit_space_details)
    assert AccessPolicy.can?(desk, :set_space_unavailable)
    assert AccessPolicy.can?(desk, :view_spaces)
    assert AccessPolicy.can?(desk, :manage_cleaning_schedule)
    refute AccessPolicy.can?(desk, :manage_spaces)

    coach = caps([:coach])
    assert AccessPolicy.can?(coach, :view_spaces)
    refute AccessPolicy.can?(coach, :edit_space_details)
    refute AccessPolicy.can?(coach, :manage_cleaning_schedule)

    refute AccessPolicy.can?(caps([:janitor]), :view_spaces)

    # A gym may let its front desk add spaces and draw floor plans too.
    granted = caps([:front_desk], role_grants: %{"front_desk" => ["manage_spaces"]})
    assert AccessPolicy.can?(granted, :manage_spaces)
    assert :manage_spaces in AccessPolicy.grantable().front_desk
  end

  test "health certificate files are for owners and admins, grantable to front desk (ADR-252)" do
    assert AccessPolicy.scope(caps([:owner]), :manage_health_certificates) == :all
    assert AccessPolicy.scope(caps([:admin]), :manage_health_certificates) == :all

    for role <- [:front_desk, :coach, :head_coach, :member, :athlete] do
      refute AccessPolicy.can?(caps([role]), :manage_health_certificates)
    end

    assert :manage_health_certificates in AccessPolicy.grantable().front_desk

    granted = caps([:front_desk], role_grants: %{"front_desk" => ["manage_health_certificates"]})
    assert AccessPolicy.can?(granted, :manage_health_certificates)
  end

  test "rights are the union of roles and the wider scope wins" do
    both = caps([:coach, :admin])
    assert AccessPolicy.scope(both, :manage_coaching) == :all
    assert AccessPolicy.can?(both, :manage_billing)

    trainee_coach = caps([:coach, :member])
    assert AccessPolicy.scope(trainee_coach, :manage_coaching) == :own
  end

  test "clients have no staff capabilities" do
    assert caps([:member]) == %{}
    assert caps([:athlete]) == %{}
  end

  describe "role grants" do
    test "owners grant anything, admins staff and clients, coaches and desk clients" do
      assert MembershipPolicy.can_grant_role?([:owner], :owner)
      assert MembershipPolicy.can_grant_role?([:owner], :admin)
      refute MembershipPolicy.can_grant_role?([:admin], :admin)
      refute MembershipPolicy.can_grant_role?([:admin], :owner)
      assert MembershipPolicy.can_grant_role?([:admin], :coach)
      assert MembershipPolicy.can_grant_role?([:admin], :janitor)
      assert MembershipPolicy.can_grant_role?([:coach], :athlete)
      assert MembershipPolicy.can_grant_role?([:front_desk], :member)
      refute MembershipPolicy.can_grant_role?([:coach], :front_desk)
      refute MembershipPolicy.can_grant_role?([:accountant], :member)
      refute MembershipPolicy.can_grant_role?([:member], :member)
    end

    test "the primary role is the most privileged of the set" do
      assert MembershipPolicy.primary_role([:member, :coach]) == :coach
      assert MembershipPolicy.primary_role([:janitor, :athlete]) == :janitor
      assert MembershipPolicy.primary_role([:admin, :owner]) == :owner
    end

    test "role sets are validated" do
      assert {:ok, [:coach, :member]} =
               MembershipPolicy.normalize_roles(["member", "coach", "coach"])

      assert {:error, :roles_required} = MembershipPolicy.normalize_roles([])
      assert {:error, :invalid_role} = MembershipPolicy.normalize_roles(["wizard"])
    end
  end
end
