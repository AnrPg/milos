defmodule MilosTraining.Application.ReportInjury do
  alias MilosTraining.Application.{BroadcastUserSync, RecordAnalyticsEvent, TenantStaffRecipients}
  alias MilosTraining.Wellbeing
  alias MilosTraining.Wellbeing.Domain.InjuryPolicy

  def call(context, user_id, params),
    do:
      MilosTraining.Wellbeing.WellbeingStore.with_context(context, fn ->
        do_call(context, user_id, params)
      end)

  def call(user_id, params), do: do_call(nil, user_id, params)

  defp do_call(context, user_id, params) do
    with {:ok, injury} <-
           Wellbeing.report_injury(
             user_id,
             user_id,
             "self",
             InjuryPolicy.self_report_params(params)
           ) do
      record_injury_reported(injury)
      broadcast_injury_reported(context, user_id, injury)
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

  defp broadcast_injury_reported(context, user_id, injury) do
    injury_id = injury.id
    admin_ids = TenantStaffRecipients.user_ids([context, injury])

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
