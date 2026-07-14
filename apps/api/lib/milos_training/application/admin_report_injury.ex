defmodule MilosTraining.Application.AdminReportInjury do
  alias MilosTraining.Application.{BroadcastUserSync, RecordAnalyticsEvent}
  alias MilosTraining.{Identity, Wellbeing}

  def call(admin_id, user_id, params) do
    with {:ok, target_user} <- training_user(user_id),
         {:ok, injury} <- Wellbeing.report_injury(target_user.id, admin_id, "admin", params) do
      RecordAnalyticsEvent.call_unsafe("injury_reported", %{
        user_id: injury.user_id,
        actor_role_snapshot: "admin",
        context_type: "injury_report",
        context_id: injury.id,
        metadata: %{
          body_area: injury.body_area,
          severity: injury.severity,
          reported_by_id: admin_id,
          reported_by_role: injury.reported_by_role,
          status: injury.status,
          tags: injury.tags
        }
      })

      broadcast_injury_reported(user_id, injury.id)
      {:ok, injury}
    end
  end

  defp training_user(user_id) do
    case Identity.find_by_id(user_id) do
      nil -> {:error, :not_found}
      %{role: role} = user when role in [:member, :athlete] -> {:ok, user}
      _user -> {:error, :injury_target_role_ineligible}
    end
  end

  defp broadcast_injury_reported(user_id, injury_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
      reason: "injury_reported",
      payload: %{injury_id: injury_id}
    )

    BroadcastUserSync.for_users(admin_ids, ["admin_wellbeing"],
      reason: "injury_reported",
      payload: %{user_id: user_id, injury_id: injury_id}
    )
  end
end
