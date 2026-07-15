defmodule MilosTraining.Identity.UpdateRoleTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Identity
  alias MilosTraining.TestFixtures

  test "concurrent demotions cannot remove every admin" do
    first_admin = TestFixtures.admin_fixture(%{nickname: "concurrent_admin_one"})
    second_admin = TestFixtures.admin_fixture(%{nickname: "concurrent_admin_two"})
    parent = self()

    tasks =
      for admin <- [first_admin, second_admin] do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(MilosTraining.Repo, parent, self())
          Identity.update_role(admin.id, :member)
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :last_admin}, &1)) == 1
    assert length(Identity.list_by_role(:admin)) == 1
  end
end
