defmodule MilosTraining.Messaging.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Messaging.{MessageStore, ThreadStore}
  alias MilosTraining.{Organizations, TestFixtures}

  test "direct threads and messages are isolated by organization context" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    context_a = tenant_context_fixture(admin, "First Messaging Gym")
    context_b = tenant_context_fixture(admin, "Second Messaging Gym")

    assert {:ok, thread_a} =
             ThreadStore.with_tenant_context(context_a, fn ->
               ThreadStore.get_or_create_thread(
                 %{
                   context_type: :direct,
                   created_by_id: admin.id,
                   direct_key: direct_key(admin, member)
                 },
                 [admin.id, member.id]
               )
             end)

    assert {:ok, message_a} =
             MessageStore.with_tenant_context(context_a, fn ->
               MessageStore.create_message(%{
                 organization_id: context_a.organization_id,
                 thread_id: thread_a.id,
                 sender_id: admin.id,
                 body: "First tenant",
                 message_type: :chat
               })
             end)

    assert {:ok, thread_b} =
             ThreadStore.with_tenant_context(context_b, fn ->
               ThreadStore.get_or_create_thread(
                 %{
                   context_type: :direct,
                   created_by_id: admin.id,
                   direct_key: direct_key(admin, member)
                 },
                 [admin.id, member.id]
               )
             end)

    assert thread_a.id != thread_b.id
    assert thread_a.organization_id == context_a.organization_id
    assert thread_b.organization_id == context_b.organization_id

    assert ThreadStore.with_tenant_context(context_b, fn ->
             ThreadStore.get_thread(thread_a.id)
           end) == nil

    assert MessageStore.with_tenant_context(context_b, fn ->
             MessageStore.get_message(message_a.id)
           end) == nil
  end

  defp tenant_context_fixture(owner, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end

  defp direct_key(left, right), do: [left.id, right.id] |> Enum.sort() |> Enum.join(":")
end
