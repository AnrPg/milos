defmodule Palee.Application.ChangeInjury do
  @moduledoc """
  Updates and reopenings of an injury report (ADR-140 §3). Each one is a
  timestamped event on the injury's timeline. The member changes their own
  user-visible reports; staff change reports of their gym.
  """

  alias Palee.Application.{BroadcastUserSync, RecordAnalyticsEvent, TenantStaffRecipients}
  alias Palee.Wellbeing
  alias Palee.Wellbeing.Domain.InjuryPolicy

  @doc "The member updates one of their own injuries."
  def update_mine(context, user_id, injury_report_id, params),
    do: mine(context, user_id, injury_report_id, &Wellbeing.update_injury(&1, user_id, params))

  @doc "The member reopens one of their own healed injuries."
  def reopen_mine(context, user_id, injury_report_id),
    do: mine(context, user_id, injury_report_id, &Wellbeing.reopen_injury(&1, user_id))

  @doc "Staff update an injury report of their gym."
  def update(context, actor_id, injury_report_id, params),
    do: staff(context, injury_report_id, &Wellbeing.update_injury(&1, actor_id, params))

  @doc "Staff reopen an injury report of their gym."
  def reopen(context, actor_id, injury_report_id),
    do: staff(context, injury_report_id, &Wellbeing.reopen_injury(&1, actor_id))

  defp mine(context, user_id, injury_report_id, change) do
    Wellbeing.with_tenant_context(context, fn ->
      with %{} = injury <- Wellbeing.get_injury_for_user(user_id, injury_report_id),
           true <- InjuryPolicy.owned_by_user?(injury, user_id),
           {:ok, changed} <- change.(injury_report_id) do
        announce(context, changed)
      else
        {:error, _reason} = error -> error
        _hidden -> {:error, :not_found}
      end
    end)
  end

  defp staff(context, injury_report_id, change) do
    Wellbeing.with_tenant_context(context, fn ->
      with {:ok, changed} <- change.(injury_report_id), do: announce(context, changed)
    end)
  end

  defp announce(context, injury) do
    event = List.last(injury.events)

    RecordAnalyticsEvent.call_unsafe("injury_#{event.event_type}", %{
      user_id: injury.user_id,
      context_type: "injury_report",
      context_id: injury.id,
      metadata: %{
        actor_id: event.actor_id,
        body_area: injury.body_area,
        severity: injury.severity,
        changed_fields: event.payload |> Map.get("changes", []) |> Enum.map(& &1["field"])
      }
    })

    BroadcastUserSync.for_user(injury.user_id, ["my_wellbeing"],
      reason: "injury_#{event.event_type}",
      payload: %{injury_id: injury.id}
    )

    BroadcastUserSync.for_users(
      TenantStaffRecipients.user_ids([context, injury]),
      ["admin_wellbeing"],
      reason: "injury_#{event.event_type}",
      payload: %{user_id: injury.user_id, injury_id: injury.id}
    )

    {:ok, injury}
  end
end
