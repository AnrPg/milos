defmodule MilosTraining.Identity.Domain.AdminProfilePolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Identity.Domain.AdminProfilePolicy

  test "athletes receive person sections plus coaching while admins stay role-safe" do
    assert "finance" in AdminProfilePolicy.sections(:athlete)
    assert "coaching_context" in AdminProfilePolicy.sections(:athlete)
    refute "coaching_context" in AdminProfilePolicy.sections(:member)
    assert AdminProfilePolicy.sections(:admin) == ["overview", "messages", "admin_actions"]
  end

  test "operational links lead to owning workspaces without duplicating workflows" do
    links = AdminProfilePolicy.operational_links(%{id: "athlete-id", role: :athlete})

    assert links.finance == "/admin/finance"
    assert links.personal_coaching == "/admin/coaching-assignments"
    refute Map.has_key?(links, :classes)
  end
end
