defmodule Palee.Application.ChangeInjury do
  @moduledoc """
  Updates and reopenings of an injury report (ADR-140 §3). Each one is a
  timestamped event on the injury's timeline. The member changes their own
  user-visible reports; staff change reports their gym keeps, about people
  they reach (`view_health`, a coach's own clients; ADR-286). A member's own
  report stays theirs: staff read it, only the member changes it.
  """

  alias Palee.Application.{BroadcastUserSync, RecordAnalyticsEvent, StaffInjuryAccess}
  alias Palee.Wellbeing
  alias Palee.Wellbeing.Domain.InjuryPolicy

  @doc "The member updates one of their own injuries."
  def update_mine(context, user_id, injury_report_id, params),
    do: mine(context, user_id, injury_report_id, &Wellbeing.update_injury(&1, user_id, params))

  @doc "The member reopens one of their own healed injuries."
  def reopen_mine(context, user_id, injury_report_id),
    do: mine(context, user_id, injury_report_id, &Wellbeing.reopen_injury(&1, user_id))

  @doc """
  The member turns «Να το δει το box μου» on or off for one of their own
  reports (ADR-286). The boxes' staff lose or gain it at once.
  """
  def share_mine(context, user_id, injury_report_id, shared?) when is_boolean(shared?) do
    Wellbeing.with_tenant_context(context, fn ->
      before = Wellbeing.get_injury_for_user(user_id, injury_report_id)

      with {:ok, injury} <- Wellbeing.set_injury_box_sharing(injury_report_id, user_id, shared?) do
        BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
          reason: "injury_sharing_changed",
          payload: %{injury_id: injury.id}
        )

        # Tell the boxes either way: those who just lost it refresh too.
        staff =
          StaffInjuryAccess.staff_user_ids(context, %{(before || injury) | shared_with_box: true})

        BroadcastUserSync.for_users(staff, ["admin_wellbeing"],
          reason: "injury_sharing_changed",
          payload: %{user_id: user_id, injury_id: injury.id}
        )

        {:ok, injury}
      end
    end)
  end

  def share_mine(_context, _user_id, _injury_report_id, _shared?), do: {:error, :invalid_sharing}

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
      with {:ok, _injury} <- StaffInjuryAccess.changeable(context, injury_report_id),
           {:ok, changed} <- change.(injury_report_id),
           do: announce(context, changed)
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
      StaffInjuryAccess.staff_user_ids(context, injury),
      ["admin_wellbeing"],
      reason: "injury_#{event.event_type}",
      payload: %{user_id: injury.user_id, injury_id: injury.id}
    )

    {:ok, injury}
  end
end
