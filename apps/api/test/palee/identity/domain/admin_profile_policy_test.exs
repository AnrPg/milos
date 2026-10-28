defmodule Palee.Identity.Domain.AdminProfilePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Identity.Domain.AdminProfilePolicy

  test "athletes receive person sections plus coaching while staff stay role-safe" do
    assert "finance" in AdminProfilePolicy.sections([:athlete])
    assert "coaching_context" in AdminProfilePolicy.sections([:athlete])
    refute "coaching_context" in AdminProfilePolicy.sections([:member])
    refute "finance" in AdminProfilePolicy.sections([:admin])
    assert "admin_actions" in AdminProfilePolicy.sections([:admin])
  end

  # ADR-217: sections follow the roles held in the gym, never users.role.
  test "staff-only people never get a finance section; staff who are also clients do" do
    for roles <- [[:owner], [:coach], [:front_desk], [:accountant], [:janitor]] do
      refute "finance" in AdminProfilePolicy.sections(roles)
      refute AdminProfilePolicy.finance_available?(roles)
    end

    assert "finance" in AdminProfilePolicy.sections([:coach, :member])
    assert AdminProfilePolicy.finance_available?(["owner", "athlete"])
    assert AdminProfilePolicy.coaching_available?([:coach, :athlete])
    refute AdminProfilePolicy.coaching_available?([:coach])
  end

  test "operational links lead to owning workspaces without duplicating workflows" do
    links = AdminProfilePolicy.operational_links(%{id: "athlete-id"}, [:athlete])

    assert links.finance == "/admin/finance"
    assert links.personal_coaching == "/admin/coaching-assignments"
    refute Map.has_key?(links, :classes)
  end

  test "operational links stay inside the organization when a slug is known" do
    links = AdminProfilePolicy.operational_links(%{id: "member-id"}, [:member], "atlas-gym")

    assert links.finance == "/org/atlas-gym/admin/finance"
    assert links.classes == "/org/atlas-gym/admin/class-schedule"
    assert links.messages == "/messages"
  end

  test "an owner's links carry no finance or coaching" do
    links = AdminProfilePolicy.operational_links(%{id: "owner-id"}, [:owner])

    refute Map.has_key?(links, :finance)
    refute Map.has_key?(links, :personal_coaching)
  end
end
