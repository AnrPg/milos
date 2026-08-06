defmodule MilosTraining.Organizations.Domain.AdminPathTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.AdminPath

  test "prefixes admin paths with the organization slug" do
    assert AdminPath.admin_url("/admin/finance", "atlas-gym") == "/org/atlas-gym/admin/finance"

    assert AdminPath.admin_url("/admin/coaching-assignments?date=2026-07-21", "atlas-gym") ==
             "/org/atlas-gym/admin/coaching-assignments?date=2026-07-21"
  end

  test "falls back to the bare path when no slug is resolvable" do
    assert AdminPath.admin_url("/admin/finance", nil) == "/admin/finance"
    assert AdminPath.admin_url("/admin/finance", "") == "/admin/finance"
  end

  test "leaves the root path unscoped" do
    assert AdminPath.admin_url("/", "atlas-gym") == "/"
  end
end
