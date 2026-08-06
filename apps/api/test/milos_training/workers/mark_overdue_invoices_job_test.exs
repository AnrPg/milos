defmodule MilosTraining.Workers.MarkOverdueInvoicesJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.{Finance, Organizations}
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workers.MarkOverdueInvoicesJob

  test "marks an overdue invoice as overdue for a non-legacy organization" do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    context = tenant_context_fixture(owner, "Overdue Job Gym")

    assert {:ok, membership} =
             Finance.upsert_membership(context, member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, invoice} =
             Finance.create_invoice(context, membership.id, %{
               amount_cents: 5_000,
               description: "Overdue job test invoice",
               due_date: Date.add(Date.utc_today(), 7)
             })

    assert {:ok, issued_invoice} = Finance.issue_invoice(context, invoice.id, %{})
    assert issued_invoice.status == "issued"

    assert {:ok, _backdated} =
             Finance.update_invoice(context, invoice.id, %{
               due_date: Date.add(Date.utc_today(), -7)
             })

    assert :ok = perform_job(MarkOverdueInvoicesJob, %{})

    assert {:ok, refreshed} = Finance.get_invoice(context, invoice.id)
    assert refreshed.status == "overdue"
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
