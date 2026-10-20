defmodule MilosTraining.Application.WellnessRLSTest do
  @moduledoc """
  ADR-159 under real Row Level Security: wellness entries and cravings are the
  member's own, private by default; another person never sees them; a coach
  of the provenance gym reads them only once the member widens the rung;
  preferences are the owner's alone.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    ChangeCraving,
    ChangeWellnessEntry,
    EraseMyWellness,
    GetMyWellness,
    LogCraving,
    LogWellnessEntry,
    SetWellnessPreferences
  }

  alias MilosTraining.Identity.UserContext
  alias MilosTraining.{Organizations, Wellness}

  @now ~U[2026-10-20 10:00:00Z]

  setup do
    fixtures =
      bypass_rls(fn ->
        {:ok, gym} = Organizations.create_organization(%{name: "Wellness Gym"})
        coach = user_fixture()
        member = user_fixture()
        other = user_fixture()
        add!(gym, coach, :coach)
        add!(gym, member, :member)
        %{gym: gym, coach: coach, member: member, other: other}
      end)

    Map.merge(fixtures, %{
      member_ctx: UserContext.new(fixtures.member),
      other_ctx: UserContext.new(fixtures.other),
      coach_ctx: tenant!(fixtures.coach, fixtures.gym)
    })
  end

  test "entries land on the member's local day, privately; nobody else sees them", ctx do
    assert {:ok, water} =
             LogWellnessEntry.call(
               ctx.member_ctx,
               %{
                 "kind" => "water",
                 "value" => %{"ml" => 250},
                 "occurred_tz" => "Europe/Athens",
                 "occurred_at" => "2026-10-19T22:30:00Z"
               },
               @now
             )

    assert water.occurred_on == ~D[2026-10-20]
    assert water.journal_visibility == "private"
    assert water.source == "manual"

    assert {:ok, night} =
             LogWellnessEntry.call(
               ctx.member_ctx,
               %{
                 "kind" => "sleep",
                 "occurred_tz" => "Europe/Athens",
                 "value" => %{
                   "bed_at" => "2026-10-19T23:40:00+03:00",
                   "wake_at" => "2026-10-20T06:50:00+03:00",
                   "quality" => 4
                 }
               },
               @now
             )

    assert night.occurred_at == ~U[2026-10-20 03:50:00.000000Z]
    assert night.occurred_on == ~D[2026-10-20]

    assert {:ok, %{entries: [_, _]}} =
             GetMyWellness.call(ctx.member_ctx, %{"from" => "2026-10-20", "to" => "2026-10-20"})

    assert {:ok, %{entries: [], days: [%{water: %{ml: 0}}]}} =
             GetMyWellness.call(ctx.other_ctx, %{"from" => "2026-10-20", "to" => "2026-10-20"})

    assert {:error, :not_found} = ChangeWellnessEntry.delete(ctx.other_ctx, water.id, @now)
  end

  test "the coach of the provenance gym reads an entry only on a rung that reaches them", ctx do
    {:ok, meal} =
      LogWellnessEntry.call(
        ctx.member_ctx,
        %{"kind" => "meal", "value" => %{"slot" => "lunch"}, "organization_slug" => ctx.gym.slug},
        @now
      )

    assert meal.organization_id == ctx.gym.id
    assert coach_sees(ctx) == []

    {:ok, _shared} =
      Wellness.with_context(ctx.member_ctx, fn ->
        ctx.member.id
        |> then(&Wellness.get_entry(meal.id, &1))
        |> Wellness.set_entry_visibility("coach_can_view")
      end)

    assert [id] = coach_sees(ctx)
    assert id == meal.id
  end

  test "a meal outside a gym the member belongs to is refused", ctx do
    {:ok, foreign} = bypass_rls(fn -> Organizations.create_organization(%{name: "Other Gym"}) end)

    assert {:error, :wellness_organization_unavailable} =
             LogWellnessEntry.call(
               ctx.member_ctx,
               %{"kind" => "meal", "value" => %{}, "organization_slug" => foreign.slug},
               @now
             )
  end

  test "entries are refused in the future or more than a week back", ctx do
    for at <- ["2026-10-20T11:00:00Z", "2026-10-12T09:00:00Z"] do
      assert {:error, _reason} =
               LogWellnessEntry.call(
                 ctx.member_ctx,
                 %{"kind" => "water", "value" => %{"ml" => 250}, "occurred_at" => at},
                 @now
               )
    end
  end

  test "a correction moves the entry and keeps the value whole", ctx do
    {:ok, entry} =
      LogWellnessEntry.call(
        ctx.member_ctx,
        %{"kind" => "sleep", "value" => %{"minutes" => 400}},
        @now
      )

    assert {:ok, changed} =
             ChangeWellnessEntry.update(
               ctx.member_ctx,
               entry.id,
               %{"value" => %{"minutes" => 430, "quality" => 3}},
               @now
             )

    assert changed.value == %{"minutes" => 430, "quality" => 3, "nap" => false}
    assert changed.corrected_at == nil
  end

  test "a device reading is deduplicated and a member's correction wins over later syncs", ctx do
    attrs = %{
      user_id: ctx.member.id,
      kind: "sleep",
      occurred_at: @now,
      occurred_tz: "UTC",
      occurred_on: ~D[2026-10-20],
      value: %{"minutes" => 400, "nap" => false},
      source: "garmin",
      external_id: "night-1"
    }

    Wellness.with_context(ctx.member_ctx, fn ->
      assert {:ok, first} = Wellness.upsert_device_entry(attrs)

      assert {:ok, again} =
               Wellness.upsert_device_entry(%{attrs | value: %{"minutes" => 410, "nap" => false}})

      assert again.id == first.id and again.value["minutes"] == 410
    end)

    {:ok, corrected} =
      ChangeWellnessEntry.update(
        ctx.member_ctx,
        first_id(ctx),
        %{"value" => %{"minutes" => 450}},
        @now
      )

    assert corrected.corrected_at

    Wellness.with_context(ctx.member_ctx, fn ->
      assert {:ok, kept} =
               Wellness.upsert_device_entry(%{attrs | value: %{"minutes" => 300, "nap" => false}})

      assert kept.value["minutes"] == 450
    end)
  end

  test "a craving is logged in the moment, followed up once, and settled later", ctx do
    assert {:ok, craving} =
             LogCraving.call(
               ctx.member_ctx,
               %{
                 "intensity" => 8,
                 "triggers" => ["fatigue", "stress"],
                 "support_requested" => true,
                 "occurred_tz" => "Europe/Athens"
               },
               @now
             )

    assert craving.triggers == ["stress", "fatigue"]
    assert craving.outcome == nil
    assert craving.support_requested_at == ~U[2026-10-20 10:00:00.000000Z]
    assert craving.follow_up_at == ~U[2026-10-20 10:20:00.000000Z]
    assert craving.journal_visibility == "private"

    later = ~U[2026-10-20 10:25:00.000000Z]

    assert {:ok, settled} =
             ChangeCraving.update(ctx.member_ctx, craving.id, %{"outcome" => "resisted"}, later)

    assert settled.outcome == "resisted"
    assert settled.outcome_at == later
    assert settled.follow_up_at == nil
    assert settled.support_requested_at == ~U[2026-10-20 10:00:00.000000Z]

    assert {:error, %Ecto.Changeset{}} =
             LogCraving.call(ctx.member_ctx, %{"intensity" => 11}, @now)

    assert {:error, :invalid_craving_trigger} =
             LogCraving.call(ctx.member_ctx, %{"intensity" => 5, "triggers" => ["sadness"]}, @now)

    assert {:ok, %{cravings: []}} =
             GetMyWellness.call(ctx.other_ctx, %{"from" => "2026-10-20", "to" => "2026-10-20"})
  end

  test "targets are the member's own and drive the day summary; erase removes a section", ctx do
    assert {:ok, prefs} =
             SetWellnessPreferences.call(ctx.member_ctx, %{
               "water_goal_ml" => 1_000,
               "glass_ml" => 500
             })

    assert prefs.water_goal_ml == 1_000

    for _ <- 1..2,
        do:
          {:ok, _} =
            LogWellnessEntry.call(
              ctx.member_ctx,
              %{"kind" => "water", "value" => %{"ml" => 500}},
              @now
            )

    {:ok, _} = LogCraving.call(ctx.member_ctx, %{"intensity" => 5}, @now)

    assert {:ok, %{days: [%{water: %{ml: 1_000, status: "full"}, cravings: %{count: 1}}]}} =
             GetMyWellness.call(ctx.member_ctx, %{"from" => "2026-10-20", "to" => "2026-10-20"})

    assert Wellness.with_context(ctx.other_ctx, fn -> Wellness.preferences(ctx.other.id) end).water_goal_ml ==
             2_000

    assert {:ok, %{"wellness" => 2}} =
             EraseMyWellness.call(ctx.member_ctx, %{"sections" => "wellness"})

    assert {:ok, %{entries: [], cravings: [_], preferences: %{water_goal_ml: 2_000}}} =
             GetMyWellness.call(ctx.member_ctx, %{"from" => "2026-10-20", "to" => "2026-10-20"})

    assert {:error, :unknown_wellness_section} =
             EraseMyWellness.call(ctx.member_ctx, %{"sections" => "body"})
  end

  defp first_id(ctx) do
    Wellness.with_context(ctx.member_ctx, fn ->
      [entry] = Wellness.list_entries(ctx.member.id, ~D[2026-10-20], ~D[2026-10-20])
      entry.id
    end)
  end

  defp coach_sees(ctx) do
    Wellness.with_context(ctx.coach_ctx, fn ->
      ctx.member.id |> Wellness.list_entries(~D[2026-10-01], ~D[2026-10-31]) |> Enum.map(& &1.id)
    end)
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
