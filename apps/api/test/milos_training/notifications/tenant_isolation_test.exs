defmodule MilosTraining.Notifications.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  import Ecto.Query

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

    # normalize_notification/1 does not surface organization_id, so assert the
    # persisted column directly - this is the tenant boundary every scoped
    # query depends on.
    assert stored_organization_id(notification_a.id) == context_a.organization_id
    assert stored_organization_id(notification_b.id) == context_b.organization_id
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
    # org A. The inbox read is not org-partitioned (see the known-gap test
    # below), so assert on the surviving rows' organization_id column instead.
    surviving =
      context_b
      |> user_notifications(member)
      |> Enum.filter(&(to_string(&1.type) == "booking_pending"))
      |> Enum.map(&stored_organization_id(&1.id))

    assert context_b.organization_id in surviving
    refute context_a.organization_id in surviving
  end

  @tag :documents_current_behaviour
  test "KNOWN GAP: the personal inbox is user-scoped only, so it spans organizations", %{
    member: member,
    context_a: context_a,
    context_b: context_b
  } do
    {:ok, _} = create_notification(context_a, member, "org-a body")
    {:ok, _} = create_notification(context_b, member, "org-b body")

    # Every inbox read in EctoNotificationStore applies scoped_to_user/1 but not
    # scoped_to_organization/1, so a member reading their inbox while org B is
    # open still sees the notification raised in org A. Recorded here so the
    # behaviour is visible rather than assumed; whether a personal inbox should
    # be partitioned per organization is a product decision, not a code fix to
    # make silently. See F-14 follow-up in the audit findings.
    bodies =
      context_b
      |> user_notifications(member)
      |> Enum.map(& &1.payload["body"])

    assert "org-b body" in bodies
    assert "org-a body" in bodies
  end

  defp stored_organization_id(notification_id) do
    MilosTraining.Repo.one!(
      from(n in "notifications",
        where: n.id == type(^notification_id, :binary_id),
        select: type(n.organization_id, :binary_id)
      )
    )
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
