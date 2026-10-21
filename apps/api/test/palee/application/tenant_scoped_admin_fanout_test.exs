defmodule Palee.Application.TenantScopedAdminFanoutTest do
  @moduledoc """
  TD-044: admin realtime fanout must reach only the staff of the acting
  organization — never the staff of another tenant and never accounts that
  merely carry the global `users.role == :admin`.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{
    AdminReportInjury,
    CreateDraftWorkout,
    MarkMyInjuryHealed,
    CreateSeasonalChallenge,
    ReplaceScaleLevels,
    UpdateAdminSettings
  }

  alias Palee.Identity.UserContext
  alias Palee.Organizations

  setup do
    Phoenix.PubSub.subscribe(Palee.PubSub, "user:sync")

    {org_a, owner_a, context_a} = tenant_with_owner!("Fanout Tenant A")
    {_org_b, owner_b, _context_b} = tenant_with_owner!("Fanout Tenant B")
    global_admin = admin_fixture()

    %{
      org_a: org_a,
      owner_a: owner_a,
      context_a: context_a,
      owner_b: owner_b,
      global_admin: global_admin
    }
  end

  test "draft creation syncs only the acting tenant's staff", ctx do
    assert {:ok, draft} = CreateDraftWorkout.call(ctx.context_a, ctx.owner_a)

    assert_scoped(ctx, "admin_workouts", "draft_created", %{draft_id: draft.id})
  end

  test "seasonal challenge creation syncs only the acting tenant's staff", ctx do
    params = %{
      title: "Tenant Week",
      description: "Two workouts",
      criteria_type: "workout_count",
      criteria_value: %{count: 2},
      badge_key: "challenge_tenant_week_#{System.unique_integer([:positive])}",
      badge_label: "Tenant Week",
      starts_at: Date.utc_today(),
      ends_at: Date.add(Date.utc_today(), 7)
    }

    assert {:ok, challenge} = CreateSeasonalChallenge.call(ctx.context_a, ctx.owner_a.id, params)

    assert_scoped(ctx, "admin_challenges", "challenge_created", %{challenge_id: challenge.id})
  end

  test "admin settings updates sync only the acting tenant's staff", ctx do
    assert {:ok, _settings} = UpdateAdminSettings.call(ctx.context_a, %{})

    assert_scoped(ctx, "admin_settings", "admin_settings_updated", %{})
  end

  test "scale level replacement syncs only the acting tenant's staff", ctx do
    assert {:ok, _levels} =
             ReplaceScaleLevels.call(ctx.context_a, [
               %{"slug" => "scaled", "label" => "Scaled", "sort_order" => 1},
               %{"slug" => "rx", "label" => "Rx", "sort_order" => 2}
             ])

    assert_scoped(ctx, "admin_workouts", "scale_levels_updated", %{})
  end

  test "a member healing a tenant-reported injury syncs only that tenant's staff", ctx do
    member = user_fixture()
    add_membership!(ctx.org_a, member, :member)

    assert {:ok, injury} =
             AdminReportInjury.call(ctx.context_a, ctx.owner_a.id, member.id, %{
               body_area: "knee",
               severity: "mild",
               visibility: "user_and_admin"
             })

    assert injury.organization_id == ctx.org_a.id

    assert {:ok, _healed} =
             MarkMyInjuryHealed.call(UserContext.new(member, %{}), member.id, injury.id, %{})

    assert_scoped(ctx, "admin_wellbeing", "injury_healed", %{injury_id: injury.id})
  end

  defp assert_scoped(ctx, scope, reason, payload) do
    owner_a_id = ctx.owner_a.id

    assert_receive {:user_sync,
                    %{user_id: ^owner_a_id, scopes: [^scope], reason: ^reason} = event},
                   1_000

    assert Map.take(event.payload || %{}, Map.keys(payload)) == payload

    for outsider <- [ctx.owner_b.id, ctx.global_admin.id] do
      refute_receive {:user_sync, %{user_id: ^outsider, scopes: [^scope], reason: ^reason}}, 100
    end
  end

  defp tenant_with_owner!(name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})
    owner = user_fixture()
    add_membership!(organization, owner, :owner)

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {organization, owner, context}
  end

  defp add_membership!(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
