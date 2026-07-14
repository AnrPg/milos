defmodule MilosTraining.Application.MarkMyInjuryHealed do
  alias MilosTraining.Application.{BroadcastUserSync, RecordAnalyticsEvent}
  alias MilosTraining.{Identity, Wellbeing}
  alias MilosTraining.Wellbeing.Domain.InjuryPolicy

  def call(user_id, injury_report_id, params \\ %{}) do
    case Wellbeing.get_injury_for_user(user_id, injury_report_id) do
      injury when not is_nil(injury) ->
        healed_on = params["healed_on"] || params[:healed_on]

        with :ok <- validate_visible_to_user(injury, user_id),
             {:ok, injury} <-
               Wellbeing.mark_healed(injury_report_id, user_id, parse_date(healed_on)) do
          RecordAnalyticsEvent.call_unsafe("injury_healed", %{
            user_id: injury.user_id,
            context_type: "injury_report",
            context_id: injury.id,
            metadata: %{
              actor_id: user_id,
              body_area: injury.body_area,
              severity: injury.severity,
              healed_on: injury.healed_on
            }
          })

          broadcast_injury_healed(injury)
          {:ok, injury}
        end

      _other ->
        {:error, :not_found}
    end
  end

  defp broadcast_injury_healed(injury) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_user(injury.user_id, ["my_wellbeing"],
      reason: "injury_healed",
      payload: %{injury_id: injury.id}
    )

    BroadcastUserSync.for_users(admin_ids, ["admin_wellbeing"],
      reason: "injury_healed",
      payload: %{user_id: injury.user_id, injury_id: injury.id}
    )
  end

  defp validate_visible_to_user(injury, user_id) do
    if InjuryPolicy.owned_by_user?(injury, user_id) and
         injury.visibility == "user_and_admin" do
      :ok
    else
      {:error, :not_found}
    end
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
