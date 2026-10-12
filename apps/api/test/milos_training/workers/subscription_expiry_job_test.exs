defmodule MilosTraining.Workers.SubscriptionExpiryJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.{Finance, Organizations, Repo}
  alias MilosTraining.Application.AuthorizeFinanceEntitlement
  alias MilosTraining.Scheduling.{Booking, ScheduledClass}
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workers.SubscriptionExpiryJob

  setup do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    context = tenant_context_fixture(owner, "Expiry Gym #{System.unique_integer([:positive])}")

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, package} =
      Finance.create_package(context, %{
        code: "monthly-#{System.unique_integer([:positive])}",
        name: "Unlimited monthly",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 0
      })

    {:ok, subscription} =
      Finance.assign_package(context, membership.id, package.id, %{
        starts_on: Date.add(Date.utc_today(), -27)
      })

    %{
      context: context,
      member: member,
      subscription: subscription,
      organization_id: context.organization_id
    }
  end

  defp end_subscription_on(subscription, ends_on) do
    Repo.query!("UPDATE membership_package_subscriptions SET ends_on = $1 WHERE id = $2", [
      ends_on,
      Ecto.UUID.dump!(subscription.id)
    ])
  end

  defp notifications(user_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT type, payload FROM notifications WHERE user_id = $1 ORDER BY inserted_at",
        [
          Ecto.UUID.dump!(user_id)
        ]
      )

    rows
  end

  test "reminds the client once before the subscription ends", ctx do
    end_subscription_on(ctx.subscription, Date.add(Date.utc_today(), 3))

    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert :ok = perform_job(SubscriptionExpiryJob, %{})

    assert [["subscription_expiring", payload]] = notifications(ctx.member.id)
    assert payload["days_left"] == 3
    assert payload["grace_days"] == 3
    assert payload["package_name"] == "Unlimited monthly"
  end

  test "a renewed subscription gets no reminder", ctx do
    end_subscription_on(ctx.subscription, Date.add(Date.utc_today(), 3))

    Repo.query!(
      """
      INSERT INTO membership_package_subscriptions
        (id, organization_id, membership_id, membership_package_id, status, starts_on, ends_on,
         package_code_snapshot, package_family_snapshot, billing_period_snapshot, inserted_at, updated_at)
      SELECT gen_random_uuid(), organization_id, membership_id, membership_package_id, 'active',
             ends_on + 1, ends_on + 31, package_code_snapshot, package_family_snapshot,
             billing_period_snapshot, now(), now()
      FROM membership_package_subscriptions WHERE id = $1
      """,
      [Ecto.UUID.dump!(ctx.subscription.id)]
    )

    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert notifications(ctx.member.id) == []
  end

  test "after the end the client keeps access during the grace days, then loses it", ctx do
    end_subscription_on(ctx.subscription, Date.add(Date.utc_today(), -1))

    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert [["subscription_grace", payload]] = notifications(ctx.member.id)
    assert payload["grace_until"] == Date.to_iso8601(Date.add(Date.utc_today(), 2))

    assert %{status: "grace", source: "subscription_grace"} =
             Finance.get_effective_entitlement(ctx.context, ctx.member.id)

    end_subscription_on(ctx.subscription, Date.add(Date.utc_today(), -5))

    assert %{status: "inactive"} = Finance.get_effective_entitlement(ctx.context, ctx.member.id)
  end

  test "when the slack is over every entitlement is revoked and upcoming bookings are cancelled",
       ctx do
    end_subscription_on(ctx.subscription, Date.add(Date.utc_today(), -1))
    assert :ok = perform_job(SubscriptionExpiryJob, %{})

    class_type = MilosTraining.TestFixtures.class_type_fixture(%{tenant_context: ctx.context})

    slot =
      Repo.insert!(%ScheduledClass{
        organization_id: ctx.organization_id,
        class_type_id: class_type.id,
        name: "Saturday WOD",
        scheduled_at: DateTime.add(DateTime.utc_now(), 3, :day) |> DateTime.truncate(:second),
        capacity: 10,
        master_workout_id:
          MilosTraining.TestFixtures.workout_fixture(
            MilosTraining.TestFixtures.admin_fixture(),
            %{tenant_context: ctx.context}
          ).id
      })

    booking =
      Repo.insert!(%Booking{
        organization_id: ctx.organization_id,
        scheduled_class_id: slot.id,
        user_id: ctx.member.id,
        status: :approved
      })

    # Grace is over.
    end_subscription_on(ctx.subscription, Date.add(Date.utc_today(), -5))
    assert :ok = perform_job(SubscriptionExpiryJob, %{})

    assert Repo.get(Booking, booking.id) == nil
    assert ["subscription_grace", "access_ended"] = Enum.map(notifications(ctx.member.id), &hd/1)

    assert [_, ["access_ended", %{"cancelled_bookings" => 1, "reason" => "subscription_ended"}]] =
             notifications(ctx.member.id)

    actor = %{id: ctx.member.id, role: :member}

    for request <- [
          %{channel: :in_person, capability: :book_classes},
          %{channel: :in_person, capability: :execute_class_workouts},
          %{channel: :workout_library, capability: :execute_library_workouts},
          %{channel: :personal_programming, capability: :execute_assigned_workouts}
        ] do
      assert {:error, :finance_entitlement_inactive} =
               AuthorizeFinanceEntitlement.call(ctx.context, actor, request)
    end

    # Nothing more to revoke on the next run.
    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert length(notifications(ctx.member.id)) == 2
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
