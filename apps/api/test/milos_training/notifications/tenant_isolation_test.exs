defmodule MilosTraining.Notifications.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Notifications.NotificationStore
  alias MilosTraining.{Organizations, TestFixtures}

  setup do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})

    context_a = tenant_context_fixture(owner, "First Notifications Gym", member)
    context_b = tenant_context_fixture(owner, "Second Notifications Gym", member)

    {:ok, member: member, context_a: context_a, context_b: context_b}
  end

  test "notifications are stamped with the organization they were raised in", %{
    member: member,
    context_a: context_a,
    context_b: context_b
  } do
    {:ok, notification_a} = create_notification(context_a, member, "org-a body")
    {:ok, notification_b} = create_notification(context_b, member, "org-b body")

    refute notification_a.id == notification_b.id

    assert notification_a.organization_id == context_a.organization_id
    assert notification_b.organization_id == context_b.organization_id
  end

  test "the organization-scoped delete path only reaches its own tenant's rows", %{
    member: member,
    context_a: context_a,
    context_b: context_b
  } do
    booking_id = Ecto.UUID.generate()

    for context <- [context_a, context_b] do
      {:ok, _notification} =
        NotificationStore.with_user_context(context, fn ->
          NotificationStore.create_notification(%{
            user_id: member.id,
            organization_id: context.organization_id,
            type: :booking_pending,
            payload: %{"booking_id" => booking_id}
          })
        end)
    end

    NotificationStore.with_user_context(context_a, fn ->
      NotificationStore.delete_booking_pending_for_booking(booking_id)
    end)

    # Org B's identically-keyed notification must survive a delete issued by
    # org A. The inbox read is not org-partitioned (deliberately - see below),
    # so discriminate on each surviving row's origin organization.
    surviving =
      context_b
      |> user_notifications(member)
      |> Enum.filter(&(to_string(&1.type) == "booking_pending"))
      |> Enum.map(& &1.organization_id)

    assert context_b.organization_id in surviving
    refute context_a.organization_id in surviving
  end

  test "the personal inbox spans organizations and labels each item's origin", %{
    member: member,
    context_a: context_a,
    context_b: context_b
  } do
    {:ok, _} = create_notification(context_a, member, "org-a body")
    {:ok, _} = create_notification(context_b, member, "org-b body")

    # PRODUCT DECISION (2026-08-07, F-28): the inbox is deliberately not
    # partitioned - a member should not miss a notification just because they
    # have a different gym selected. Inbox reads therefore apply
    # scoped_to_user/1 without scoped_to_organization/1.
    #
    # The corresponding requirement is that each item carries its origin so the
    # client can visually flag anything raised outside the active organization.
    # Without organization_id on the payload that is impossible, so assert it.
    notifications = user_notifications(context_b, member)
    bodies = Enum.map(notifications, & &1.payload["body"])

    assert "org-b body" in bodies
    assert "org-a body" in bodies

    origins =
      Map.new(notifications, fn notification ->
        {notification.payload["body"], notification.organization_id}
      end)

    assert origins["org-a body"] == context_a.organization_id
    assert origins["org-b body"] == context_b.organization_id
    refute origins["org-a body"] == origins["org-b body"]
  end

  defp user_notifications(context, member) do
    NotificationStore.with_user_context(context, fn ->
      NotificationStore.list_for_user(member.id)
    end)
  end

  defp create_notification(context, member, body) do
    NotificationStore.with_user_context(context, fn ->
      NotificationStore.create_notification(%{
        user_id: member.id,
        organization_id: context.organization_id,
        type: :admin_note,
        payload: %{"body" => body}
      })
    end)
  end

  defp tenant_context_fixture(owner, name, member) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(member, organization.slug)
    context
  end
end
