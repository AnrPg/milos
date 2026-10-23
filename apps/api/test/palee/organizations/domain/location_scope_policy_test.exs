defmodule Palee.Organizations.Domain.LocationScopePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.{AccessPolicy, LocationScopePolicy}

  @kifisia "00000000-0000-0000-0000-00000000000a"
  @marousi "00000000-0000-0000-0000-00000000000b"
  @glyfada "00000000-0000-0000-0000-00000000000c"

  describe "effective/3" do
    test "owners, clients and the «all» flag work everywhere" do
      assert LocationScopePolicy.effective([:owner], false, [@kifisia]) == :all
      assert LocationScopePolicy.effective([:owner, :coach], false, [@kifisia]) == :all
      assert LocationScopePolicy.effective([:member], false, [@kifisia]) == :all
      assert LocationScopePolicy.effective([:front_desk], true, [@kifisia]) == :all
    end

    test "branch-scoped staff work at their sorted, unique branches" do
      assert LocationScopePolicy.effective([:coach, :member], false, [
               @marousi,
               @kifisia,
               @kifisia
             ]) ==
               [@kifisia, @marousi]

      # Every branch archived: nothing located, never everything.
      assert LocationScopePolicy.effective([:front_desk], false, []) == []
    end
  end

  describe "covers?/2, authorize/2, filter/3" do
    test ":all covers everything, including things without a location" do
      assert LocationScopePolicy.covers?(:all, @glyfada)
      assert LocationScopePolicy.covers?(:all, nil)
    end

    test "a scope covers its branches only, never things without a location" do
      scope = [@kifisia]
      assert LocationScopePolicy.covers?(scope, @kifisia)
      refute LocationScopePolicy.covers?(scope, @marousi)
      refute LocationScopePolicy.covers?(scope, nil)
      assert LocationScopePolicy.authorize(scope, @marousi) == {:error, :location_out_of_scope}
      assert LocationScopePolicy.authorize(%{location_scope: scope}, @kifisia) == :ok
    end

    test "a context without a scope works everywhere" do
      assert LocationScopePolicy.covers?(%{role: :admin}, @kifisia)
      assert LocationScopePolicy.scope(%{location_scope: :all}) == :all
    end

    test "filter keeps the located items in scope" do
      items = [
        %{id: 1, location_id: @kifisia},
        %{id: 2, location_id: @marousi},
        %{id: 3, location_id: nil}
      ]

      assert LocationScopePolicy.filter(:all, items) == items
      assert [%{id: 1}] = LocationScopePolicy.filter([@kifisia], items)
      assert [%{id: 2}] = LocationScopePolicy.filter([@marousi], items, & &1.location_id)
    end

    test "restrict narrows a location filter" do
      assert LocationScopePolicy.restrict(:all, nil) == nil
      assert LocationScopePolicy.restrict([@kifisia], nil) == [@kifisia]
      assert LocationScopePolicy.restrict([@kifisia], @marousi) == []
      assert LocationScopePolicy.restrict([@kifisia], [@kifisia, @marousi]) == [@kifisia]
    end
  end

  describe "desk_location/2" do
    test "a one-branch desk works at its branch; a wider one must choose" do
      assert LocationScopePolicy.desk_location(:all, nil) == {:ok, nil}
      assert LocationScopePolicy.desk_location(:all, "") == {:ok, nil}
      assert LocationScopePolicy.desk_location([@kifisia], nil) == {:ok, @kifisia}

      assert LocationScopePolicy.desk_location([@kifisia, @marousi], nil) ==
               {:error, :location_required}

      assert LocationScopePolicy.desk_location([@kifisia], @marousi) ==
               {:error, :location_out_of_scope}

      assert LocationScopePolicy.desk_location([@kifisia, @marousi], @marousi) == {:ok, @marousi}
    end
  end

  describe "capabilities" do
    test "branch-scoped staff lose the capabilities over the whole business" do
      admin = AccessPolicy.capabilities([:admin])
      branch_manager = LocationScopePolicy.narrow_capabilities(admin, [@kifisia])

      for capability <- LocationScopePolicy.organization_wide() do
        refute Map.has_key?(branch_manager, capability), inspect(capability)
      end

      for capability <- [
            :manage_locations,
            :manage_schedule,
            :run_classes,
            :check_in,
            :grant_staff_roles,
            :take_payments,
            :manage_appointments,
            :manage_cleaning_areas,
            :manage_inventory
          ] do
        assert Map.has_key?(branch_manager, capability), inspect(capability)
      end

      assert LocationScopePolicy.narrow_capabilities(admin, :all) == admin
    end
  end

  describe "grants" do
    test "nobody grants a scope wider than their own" do
      assert LocationScopePolicy.can_grant_scope?(:all, :all)
      assert LocationScopePolicy.can_grant_scope?(:all, [@kifisia])
      assert LocationScopePolicy.can_grant_scope?([@kifisia, @marousi], [@marousi])
      refute LocationScopePolicy.can_grant_scope?([@kifisia], :all)
      refute LocationScopePolicy.can_grant_scope?([@kifisia], [@kifisia, @marousi])
      refute LocationScopePolicy.can_grant_scope?([@kifisia], [])

      assert LocationScopePolicy.authorize_grant([@kifisia], [@marousi]) ==
               {:error, :location_scope_exceeded}
    end

    test "a branch manager manages clients and the staff of their branches only" do
      assert LocationScopePolicy.can_manage?([@kifisia], [:member], :all)
      assert LocationScopePolicy.can_manage?([@kifisia], [:front_desk], [@kifisia])
      refute LocationScopePolicy.can_manage?([@kifisia], [:front_desk], [@kifisia, @marousi])
      refute LocationScopePolicy.can_manage?([@kifisia], [:coach], :all)
    end
  end

  describe "parse/2" do
    test "accepts «all» or known branches" do
      known = [@kifisia, @marousi]
      assert LocationScopePolicy.parse(%{"all_locations" => true}, known) == {:ok, :all}

      assert LocationScopePolicy.parse(%{"location_ids" => [@marousi, @kifisia]}, known) ==
               {:ok, [@kifisia, @marousi]}

      assert LocationScopePolicy.parse(%{all_locations: false, location_ids: [@glyfada]}, known) ==
               {:error, :invalid_location_scope}

      assert LocationScopePolicy.parse(%{"location_ids" => []}, known) ==
               {:error, :invalid_location_scope}

      assert LocationScopePolicy.parse(%{}, known) == {:error, :invalid_location_scope}
    end

    test "requested? tells a change apart from leaving the scope alone" do
      assert LocationScopePolicy.requested?(%{"location_ids" => [@kifisia]})
      assert LocationScopePolicy.requested?(%{all_locations: true})
      refute LocationScopePolicy.requested?(%{"role" => "coach"})
    end
  end

  describe "merge_on_redeem/3" do
    test "a client takes the invitation's branches; staff add them" do
      assert LocationScopePolicy.merge_on_redeem([:member], :all, [@kifisia]) == [@kifisia]
      assert LocationScopePolicy.merge_on_redeem([], :all, [@kifisia]) == [@kifisia]
      assert LocationScopePolicy.merge_on_redeem([:coach], :all, [@kifisia]) == :all
      assert LocationScopePolicy.merge_on_redeem([:coach], [@marousi], :all) == :all

      assert LocationScopePolicy.merge_on_redeem([:coach], [@marousi], [@kifisia]) ==
               [@kifisia, @marousi]
    end
  end
end
