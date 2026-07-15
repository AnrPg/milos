defmodule MilosTraining.Application.AdminUserDossierTest do
  use MilosTraining.DataCase, async: true

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    GetAdminUserCoachingContext,
    GetAdminUserFinance,
    GetAdminUserIncidents,
    GetAdminUserMessages,
    GetAdminUserPRs,
    GetAdminUserTrainingHistory
  }

  test "member dossier services share a stable user key and safe empty collections" do
    member = user_fixture(%{role: :member})

    assert {:ok, %{user_id: id, available: true}} = GetAdminUserFinance.call(member.id)
    assert id == member.id

    assert {:ok, %{user_id: ^id, executions: [], scores: []}} =
             GetAdminUserTrainingHistory.call(id)

    assert {:ok, %{user_id: ^id, prs: []}} = GetAdminUserPRs.call(id)
    assert {:ok, %{user_id: ^id, incidents: []}} = GetAdminUserIncidents.call(id)
    assert {:ok, %{user_id: ^id, threads: []}} = GetAdminUserMessages.call(id)

    assert {:ok, %{user_id: ^id, available: false, drill_down: nil}} =
             GetAdminUserCoachingContext.call(id)
  end

  test "all focused reads return the same not-found boundary" do
    missing_id = Ecto.UUID.generate()

    for service <- [
          GetAdminUserFinance,
          GetAdminUserTrainingHistory,
          GetAdminUserPRs,
          GetAdminUserIncidents,
          GetAdminUserMessages
        ] do
      assert {:error, :not_found} = service.call(missing_id)
    end

    assert {:error, :not_found} = GetAdminUserCoachingContext.call(missing_id)
  end
end
