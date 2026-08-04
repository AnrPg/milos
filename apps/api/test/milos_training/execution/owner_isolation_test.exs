defmodule MilosTraining.Execution.OwnerIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.TestFixtures

  test "executions are readable only through their owner user context" do
    owner = TestFixtures.user_fixture()
    other_user = TestFixtures.user_fixture()
    owner_context = %{user_id: owner.id}
    other_context = %{user_id: other_user.id}

    assert {:ok, execution} =
             ExecutionStore.with_user_context(owner_context, fn ->
               ExecutionStore.start_execution(%{
                 user_id: other_user.id,
                 source: :self_selected,
                 status: :active,
                 started_at_utc: DateTime.utc_now(),
                 started_at_tz: "UTC"
               })
             end)

    assert execution.user_id == owner.id

    assert ExecutionStore.with_user_context(owner_context, fn ->
             ExecutionStore.get_execution(execution.id)
           end)

    assert ExecutionStore.with_user_context(other_context, fn ->
             ExecutionStore.get_execution(execution.id)
           end) == nil
  end
end
