defmodule MilosTraining.WellbeingTest do
  use MilosTraining.DataCase

  alias MilosTraining.Application.{AdminReportInjury, MarkMyInjuryHealed, ReportInjury}
  alias MilosTraining.TestFixtures
  alias MilosTraining.Wellbeing

  test "reports injuries and records healing status" do
    user = TestFixtures.user_fixture()

    assert {:ok, injury} =
             Wellbeing.report_injury(user.id, user.id, "self", %{
               body_area: "shoulder",
               severity: "moderate",
               training_limitations: "No overhead pressing"
             })

    assert injury.status == "active"
    assert injury.body_area == "shoulder"

    assert {:ok, healed} = Wellbeing.mark_healed(injury.id, user.id, ~D[2026-06-11])
    assert healed.status == "healed"
    assert healed.healed_on == ~D[2026-06-11]

    assert {:error, :injury_already_healed} =
             Wellbeing.mark_healed(injury.id, user.id, ~D[2026-06-12])
  end

  test "rejects healed dates before the injury start date" do
    user = TestFixtures.user_fixture()

    assert {:ok, injury} =
             Wellbeing.report_injury(user.id, user.id, "self", %{
               body_area: "knee",
               severity: "mild",
               started_on: ~D[2026-06-10]
             })

    assert {:error, :injury_healed_before_started} =
             Wellbeing.mark_healed(injury.id, user.id, ~D[2026-06-09])
  end

  test "self-reported injuries force user visibility and remain healable" do
    user = TestFixtures.user_fixture()

    assert {:ok, injury} =
             ReportInjury.call(user.id, %{
               body_area: "ankle",
               severity: "mild",
               visibility: "admin_only"
             })

    assert injury.visibility == "user_and_admin"
    assert [%{id: injury_id}] = Wellbeing.list_injuries_for_user(user.id)
    assert injury_id == injury.id

    assert {:ok, healed} = MarkMyInjuryHealed.call(user.id, injury.id, %{})
    assert healed.status == "healed"
  end

  test "admin-created injury reports only target training accounts" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, injury} =
             AdminReportInjury.call(admin.id, member.id, %{
               body_area: "back",
               severity: "mild"
             })

    assert injury.user_id == member.id

    assert {:error, :injury_target_role_ineligible} =
             AdminReportInjury.call(admin.id, admin.id, %{
               body_area: "shoulder",
               severity: "mild"
             })
  end
end
