defmodule MilosTraining.Workers.PaymentReminderJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.{Finance, Organizations}
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workers.PaymentReminderJob

  test "sends a payment reminder for a non-legacy organization's membership with an outstanding balance" do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    context = tenant_context_fixture(owner, "Payment Reminder Gym")

    assert {:ok, membership} =
             Finance.upsert_membership(context, member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "direct"
             })

    assert {:ok, invoice} =
             Finance.create_invoice(context, membership.id, %{
               amount_cents: 4_000,
               description: "Payment reminder job test invoice",
               due_date: Date.add(Date.utc_today(), 7)
             })

    assert {:ok, _issued} = Finance.issue_invoice(context, invoice.id, %{})

    assert :ok = perform_job(PaymentReminderJob, %{})

    %{rows: [[reminded_at]]} =
      MilosTraining.Repo.query!(
        "SELECT last_payment_reminder_sent_at FROM memberships WHERE id = $1",
        [Ecto.UUID.dump!(membership.id)]
      )

    assert reminded_at != nil
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
