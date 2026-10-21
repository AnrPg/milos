defmodule Palee.Application.MarkInjuryHealed do
  alias Palee.Application.{BroadcastUserSync, RecordAnalyticsEvent, TenantStaffRecipients}
  alias Palee.Wellbeing

  def call(context, actor_id, injury_report_id, params),
    do:
      Palee.Wellbeing.WellbeingStore.with_context(context, fn ->
        do_call(context, actor_id, injury_report_id, params)
      end)

  def call(actor_id, injury_report_id, params \\ %{}),
    do: do_call(nil, actor_id, injury_report_id, params)

  defp do_call(context, actor_id, injury_report_id, params) do
    healed_on = params["healed_on"] || params[:healed_on]

    with {:ok, injury} <- Wellbeing.mark_healed(injury_report_id, actor_id, parse_date(healed_on)) do
      RecordAnalyticsEvent.call_unsafe("injury_healed", %{
        user_id: injury.user_id,
        context_type: "injury_report",
        context_id: injury.id,
        metadata: %{
          actor_id: actor_id,
          body_area: injury.body_area,
          severity: injury.severity,
          healed_on: injury.healed_on
        }
      })

      broadcast_injury_healed(context, injury)
      {:ok, injury}
    end
  end

  defp broadcast_injury_healed(context, injury) do
    admin_ids = TenantStaffRecipients.user_ids([context, injury])

    BroadcastUserSync.for_user(injury.user_id, ["my_wellbeing"],
      reason: "injury_healed",
      payload: %{injury_id: injury.id}
    )

    BroadcastUserSync.for_users(admin_ids, ["admin_wellbeing"],
      reason: "injury_healed",
      payload: %{user_id: injury.user_id, injury_id: injury.id}
    )
  end

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
