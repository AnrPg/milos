defmodule Palee.Application.DeviceData do
  @moduledoc """
  A person's device data as a whole (plan D11):

  - `delete/3`, «Διέγραψε όλα τα δεδομένα» (ADR-161, board 16 Q6; ADR-172):
    everything a provider brought in goes: its workouts (and with them the
    watch numbers on merged entries), the nights and weigh-ins it created
    (never what the person typed), the daily stats and the import log.
  - `export/2` (ADR-172): the connections, workouts, daily stats and import
    log as JSON. Nights and weigh-ins are in the Ευεξία and Σώμα exports,
    where they live.
  """

  alias Palee.Application.DevicePresenter
  alias Palee.{Body, Devices, Wellness}

  def export(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    Devices.with_context(context, fn ->
      %{
        exported_at: now,
        connections:
          user_id
          |> Devices.list_connections()
          |> Enum.map(
            &%{
              provider: &1.provider,
              status: &1.status,
              connected_at: &1.connected_at,
              last_synced_at: &1.last_synced_at,
              revoked_at: &1.revoked_at,
              sync_prefs: &1.sync_prefs
            }
          ),
        activities: user_id |> Devices.list_activities() |> Enum.map(&DevicePresenter.activity/1),
        daily_stats:
          user_id
          |> Devices.list_all_daily_stats()
          |> Enum.map(
            &%{
              on: &1.on,
              source: &1.source,
              resting_heart_rate: &1.resting_heart_rate,
              steps: &1.steps
            }
          ),
        imports:
          Devices.providers()
          |> Enum.flat_map(&Devices.list_imports(user_id, &1))
          |> Enum.sort_by(& &1.received_at, DateTime)
          |> Enum.map(
            &%{
              provider: &1.provider,
              kind: &1.kind,
              status: &1.status,
              reason: &1.reason,
              target_type: &1.target_type,
              received_at: &1.received_at
            }
          )
      }
    end)
  end

  def delete(%{user_id: user_id} = context, provider, now \\ DateTime.utc_now()) do
    Devices.with_context(context, fn ->
      imports = Devices.list_imports(user_id, provider)
      created = Enum.filter(imports, &(&1.status == "imported"))

      nights =
        created
        |> targets("wellness_entry")
        |> Enum.count(fn id ->
          case Wellness.get_entry(id, user_id) do
            %{source: ^provider} = entry -> match?({:ok, _}, Wellness.delete_entry(entry, now))
            _other -> false
          end
        end)

      weigh_ins =
        created
        |> targets("body_snapshot")
        |> Enum.count(fn id ->
          case Body.get_snapshot(context, user_id, id) do
            %{source: ^provider} -> match?({:ok, _}, Body.delete_snapshot(context, user_id, id))
            _other -> false
          end
        end)

      %{
        activities: Devices.delete_activities(user_id, provider),
        sleep: nights,
        weight: weigh_ins,
        daily_stats: Devices.delete_daily_stats(user_id, provider),
        imports: Devices.delete_imports(user_id, provider)
      }
    end)
  end

  defp targets(imports, type),
    do: for(%{target_type: ^type, target_id: id} <- imports, is_binary(id), do: id)
end
