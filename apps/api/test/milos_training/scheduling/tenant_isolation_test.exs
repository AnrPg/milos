defmodule MilosTraining.Scheduling.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.{Organizations, Scheduling}

  test "class type writes and reads are isolated by tenant context" do
    owner = user_fixture()
    first_context = tenant_context_fixture(owner, "First Scheduling Gym")
    second_context = tenant_context_fixture(owner, "Second Scheduling Gym")

    assert {:ok, first_class_type} =
             Scheduling.create_class_type(first_context, %{
               name: "Strength",
               slug: "strength",
               sort_order: 1
             })

    assert {:ok, second_class_type} =
             Scheduling.create_class_type(second_context, %{
               name: "Strength",
               slug: "strength",
               sort_order: 1
             })

    assert first_class_type.organization_id == first_context.organization_id
    assert second_class_type.organization_id == second_context.organization_id

    assert [listed_first] = Scheduling.list_class_types(first_context)
    assert listed_first.id == first_class_type.id

    assert [listed_second] = Scheduling.list_class_types(second_context)
    assert listed_second.id == second_class_type.id

    assert Scheduling.get_class_type(first_context, second_class_type.id) == nil

    assert {:error, :not_found} =
             Scheduling.update_class_type(first_context, second_class_type.id, %{name: "Forged"})
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
end
