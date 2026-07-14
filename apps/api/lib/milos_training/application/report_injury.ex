defmodule MilosTraining.Application.ReportInjury do
  alias MilosTraining.Application.{BroadcastUserSync, RecordAnalyticsEvent}
  alias MilosTraining.{Identity, Wellbeing}
  alias MilosTraining.Wellbeing.Domain.InjuryPolicy

  def call(user_id, params) do
    with {:ok, injury} <-
           Wellbeing.report_injury(
             user_id,
             user_id,
             "self",
             InjuryPolicy.self_report_params(params)
           ) do
      record_injury_reported(injury)
      broadcast_injury_reported(user_id, injury.id)
      {:ok, injury}
    end
  end

  defp record_injury_reported(injury) do
    RecordAnalyticsEvent.call_unsafe("injury_reported", %{
      user_id: injury.user_id,
      context_type: "injury_report",
      context_id: injury.id,
      metadata: %{
        body_area: injury.body_area,
        severity: injury.severity,
        reported_by_role: injury.reported_by_role,
        status: injury.status,
        tags: injury.tags
      }
    })
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
