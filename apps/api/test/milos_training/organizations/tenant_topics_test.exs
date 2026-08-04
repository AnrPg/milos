defmodule MilosTraining.Organizations.TenantTopicsTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.TenantTopics

  test "namespaces organization and personal topics independently" do
    assert TenantTopics.organization("org-1", "schedule") == "org:org-1:schedule"
    assert TenantTopics.user("user-1", "notifications") == "user:user-1:notifications"
  end
end
