defmodule MilosTraining.Workers.ReconcileEntitlementReservationsJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workers.ReconcileEntitlementReservationsJob

  test "iterates every active organization without erroring, including a non-legacy one" do
    owner = TestFixtures.admin_fixture()
    _context = tenant_context_fixture(owner, "Reconcile Reservations Gym")

    assert :ok = perform_job(ReconcileEntitlementReservationsJob, %{})
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
