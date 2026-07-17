defmodule MilosTraining.Application.PRUpdateModesTest do
  use MilosTraining.DataCase, async: true

  import MilosTraining.TestFixtures

  alias MilosTraining.Pantheon

  test "update records history while edit corrects the current result in place" do
    user = user_fixture(%{role: :member})

    assert {:ok, pr} =
             Pantheon.create_pr(user.id, %{
               "name" => "Back squat",
               "current_score" => 100,
               "unit" => "kg",
               "higher_is_better" => true,
               "beaten_on" => ~D[2026-07-01]
             })

    assert {:ok, updated} =
             Pantheon.update_pr(pr.id, user.id, %{
               "current_score" => 110,
               "beaten_on" => ~D[2026-07-17]
             })

    assert updated.current_score == 110.0
    assert {:ok, [_previous_result]} = Pantheon.get_pr_history(pr.id, user.id)

    assert {:ok, edited} =
             Pantheon.edit_pr(pr.id, user.id, %{
               "current_score" => 109,
               "notes" => "Corrected plate total"
             })

    assert edited.current_score == 109.0
    assert edited.notes == "Corrected plate total"
    assert {:ok, [_previous_result]} = Pantheon.get_pr_history(pr.id, user.id)
  end
end
