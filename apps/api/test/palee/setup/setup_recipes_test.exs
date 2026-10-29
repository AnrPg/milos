defmodule Palee.Setup.SetupRecipesTest do
  @moduledoc """
  ADR-255 end to end under Row Level Security: a recipe applied to a fresh
  business sets its settings and creates its packages and class types
  through the existing services, records who applied it, and applying it
  again changes nothing.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, member_context: 2]

  alias Palee.{Community, Facility, Finance, Gamification, Organizations, Scheduling, Setup, Trials}
  alias Palee.Application.Setup.SetupRecipes

  @now ~U[2027-02-11 09:00:00.000000Z]

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    %{organization: organization, owner: owner, context: context}
  end

  defp packages(context), do: context |> Finance.list_packages() |> Enum.map(& &1.code) |> Enum.sort()

  defp class_types(context) do
    {:ok, types} = Palee.Application.ListClassTypes.call(context, include_archived: true)
    types |> Enum.map(& &1.name) |> Enum.sort()
  end

  test "preview is a dry run: it changes nothing", %{context: context} do
    assert {:ok, plan} = SetupRecipes.preview(context, "crossfit_box")

    assert plan.change_count > 0
    assert plan.change_count == length(plan.changes)
    assert Enum.any?(plan.changes, &(&1.key == "package.setup_unlimited"))
    assert [%{area: "document", action: "manual"} | _] = plan.manual

    assert packages(context) == []
    assert Scheduling.get_settings(context).default_capacity == 12
    assert Setup.list_applications(context) == []
  end

  test "applying CrossFit box twice: the second time changes nothing", %{
    context: context,
    owner: owner
  } do
    assert {:ok, %{plan: plan, application: application}} =
             SetupRecipes.apply_recipe(context, "crossfit_box", @now)

    assert plan.change_count > 0
    assert application.recipe_key == "crossfit_box"
    assert application.recipe_version == 1
    assert application.applied_by_id == owner.id
    assert application.applied_at == @now
    assert application.change_count == plan.change_count

    # Packages, through Finance.
    assert packages(context) ==
             Enum.sort(~w(setup_drop_in setup_ten_classes setup_three_a_week setup_trial setup_unlimited))

    unlimited = Enum.find(Finance.list_packages(context), &(&1.code == "setup_unlimited"))
    assert unlimited.base_price_cents == 8_000
    assert unlimited.name == "Unlimited monthly"

    # Class types, through Scheduling.
    assert class_types(context) == Enum.sort(["WOD", "Foundations", "Weightlifting", "Open gym"])

    # Settings in each context.
    scheduling = Scheduling.get_settings(context)
    assert scheduling.default_capacity == 16
    assert scheduling.default_auto_approve == true
    assert scheduling.default_cancellation_cutoff_minutes == 120
    assert scheduling.default_booking_window_days == 7

    assert Enum.sort(Finance.get_finance_settings(context).package_modules) ==
             ~w(group_classes online_coaching open_gym)

    assert Gamification.with_tenant_context(context, &Gamification.get_settings/0).leaderboard_enabled
    assert Facility.check_in_rules(context).open_gym_requires_package

    trial = Trials.policy(context)
    assert trial.enabled
    assert trial.seats_per_class == 2
    assert trial.conversion_package_id == unlimited.id

    assert {:ok, %{"front_desk" => ["manage_billing"]}} = Organizations.get_role_grants(context)

    # Again: nothing left to do, nothing changed, the application recorded.
    before = {packages(context), class_types(context)}
    assert {:ok, %{plan: again, application: second}} =
             SetupRecipes.apply_recipe(context, "crossfit_box", @now)

    assert again.changes == []
    assert again.change_count == 0
    assert second.change_count == 0
    assert {packages(context), class_types(context)} == before
    assert {:ok, %{change_count: 0}} = SetupRecipes.preview(context, "crossfit_box")

    assert [%{change_count: 0}, %{change_count: first}] = Setup.list_applications(context)
    assert first == plan.change_count
  end

  test "a Greek business gets Greek names", %{context: context, organization: organization} do
    {1, _rows} =
      bypass_rls(fn ->
        Palee.Repo.update_all(
          from(s in Palee.Organizations.OrganizationSetting,
            where: s.organization_id == ^organization.id
          ),
          set: [default_locale: "el"]
        )
      end)

    assert {:ok, _result} = SetupRecipes.apply_recipe(context, "yoga_pilates_studio", @now)
    assert "Pilates στο στρώμα" in class_types(context)
    assert Enum.any?(Finance.list_packages(context), &(&1.name == "8 τμήματα τον μήνα"))
  end

  test "independent coach turns the business into a coach", %{context: context} do
    assert {:ok, _result} = SetupRecipes.apply_recipe(context, "independent_coach", @now)
    assert Organizations.get_provider_kind(context) == "coach"
    refute Community.community_settings(context).partners_enabled
  end

  test "only the owner applies; staff with manage_settings may preview", %{
    organization: organization
  } do
    {_admin, admin_context} = bypass_rls(fn -> member_context(organization, :admin) end)

    assert {:ok, _plan} = SetupRecipes.preview(admin_context, "open_gym")
    assert {:ok, %{can_apply: false}} = SetupRecipes.list(admin_context)
    assert {:error, :recipe_owner_only} = SetupRecipes.apply_recipe(admin_context, "open_gym")

    {_coach, coach_context} = bypass_rls(fn -> member_context(organization, :coach) end)
    assert {:error, :forbidden} = SetupRecipes.preview(coach_context, "open_gym")
  end

  test "an unknown recipe", %{context: context} do
    assert {:error, :recipe_not_found} = SetupRecipes.preview(context, "bowling_alley")
    assert {:error, :recipe_not_found} = SetupRecipes.apply_recipe(context, "bowling_alley")
  end

  test "the settings catalog marks advanced settings", %{context: context} do
    assert {:ok, catalog} = SetupRecipes.settings_catalog(context)
    grace = Enum.find(catalog.settings, &(&1.key == "finance.subscription_grace_days"))
    assert %{advanced: true, verdict: "advanced", default: 3} = grace
    assert "finance.subscription_grace_days" in catalog.advanced_settings
    assert catalog.counts["basic"] > 0
  end
end
