defmodule MilosTraining.Wellbeing.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Wellbeing.WellbeingStore
  alias MilosTraining.{Organizations, TestFixtures}

  setup do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})

    context_a = tenant_context_fixture(owner, "First Wellbeing Gym", member)
    context_b = tenant_context_fixture(owner, "Second Wellbeing Gym", member)

    {:ok, owner: owner, member: member, context_a: context_a, context_b: context_b}
  end

  test "the admin injury list only returns the acting organization's reports", %{
    owner: owner,
    member: member,
    context_a: context_a,
    context_b: context_b
  } do
    {:ok, _injury_a} = report_injury(context_a, member, owner, "shoulder")
    {:ok, _injury_b} = report_injury(context_b, member, owner, "knee")

    areas_a = admin_injury_areas(context_a)
    areas_b = admin_injury_areas(context_b)

    assert "shoulder" in areas_a
    refute "knee" in areas_a

    assert "knee" in areas_b
    refute "shoulder" in areas_b
  end

  test "the admin injury summary counts only the acting organization's reports", %{
    owner: owner,
    member: member,
    context_a: context_a,
    context_b: context_b
  } do
    {:ok, _injury_a} = report_injury(context_a, member, owner, "shoulder")
    {:ok, _injury_b} = report_injury(context_b, member, owner, "knee")

    summary_a = WellbeingStore.with_context(context_a, fn -> WellbeingStore.injury_summary(%{}) end)
    summary_b = WellbeingStore.with_context(context_b, fn -> WellbeingStore.injury_summary(%{}) end)

    assert summary_a.total == 1
    assert summary_b.total == 1
  end

  test "an admin's own reports from another organization stay out of this organization's views",
       %{owner: owner, member: member, context_a: context_a, context_b: context_b} do
    # The acting admin files a report on themselves in org A...
    {:ok, _own_report} = report_injury(context_a, owner, owner, "elbow")
    {:ok, _member_report} = report_injury(context_b, member, owner, "knee")

    # ...and must not see it while working in org B. Before the owner/tenant
    # split this leaked, because the admin listing shared the owner-scoped
    # predicate and its `user_id == <acting admin>` branch matched regardless
    # of organization.
    areas_b = admin_injury_areas(context_b)

    assert "knee" in areas_b
    refute "elbow" in areas_b

    summary_b =
      WellbeingStore.with_context(context_b, fn -> WellbeingStore.injury_summary(%{}) end)

    assert summary_b.total == 1
  end

  test "a member's own injury records follow them across organizations (by design)", %{
    owner: owner,
    member: member,
    context_a: context_a,
    context_b: context_b
  } do
    {:ok, injury_a} = report_injury(context_a, member, owner, "shoulder")
    {:ok, _injury_b} = report_injury(context_b, member, owner, "knee")

    # PRODUCT DECISION (2026-08-07, F-28): a member's health records are their
    # own and deliberately follow them across every gym they attend, rather
    # than being partitioned per tenant. scoped_to_owner_or_tenant/1's
    # disjunction is intentional for these personal reads.
    #
    # This only widens when the acting account IS the subject. An admin
    # reading a member's dossier still resolves to their own organization,
    # because the owner branch (user_id == admin) cannot match the member's
    # rows - asserted separately above.
    {:ok, member_context_b} = Organizations.resolve_tenant_context(member, context_b.organization.slug)

    own_areas =
      WellbeingStore.with_context(member_context_b, fn ->
        WellbeingStore.list_injuries_for_user(member.id)
      end)
      |> Enum.map(& &1.body_area)

    assert "knee" in own_areas
    assert "shoulder" in own_areas

    assert WellbeingStore.with_context(member_context_b, fn ->
             WellbeingStore.get_injury_for_user(member.id, injury_a.id)
           end)
  end

  defp admin_injury_areas(context) do
    WellbeingStore.with_context(context, fn -> WellbeingStore.list_injuries(%{}) end)
    |> Enum.map(& &1.body_area)
  end

  defp report_injury(context, member, actor, body_area) do
    WellbeingStore.with_context(context, fn ->
      WellbeingStore.report_injury(member.id, actor.id, "admin", %{
        "organization_id" => context.organization_id,
        "body_area" => body_area,
        "severity" => "moderate",
        "started_on" => Date.utc_today(),
        "visibility" => "user_and_admin"
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

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end
end
