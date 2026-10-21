defmodule MilosTraining.Application.DeviceData do
  @moduledoc """
  «Διέγραψε όλα τα δεδομένα Garmin» (ADR-161, board 16 Q6): everything a
  provider brought in goes: its workouts (and with them the watch numbers on
  merged entries), the nights and weigh-ins it created (never what the
  person typed), the daily stats and the import log.
  """

  alias MilosTraining.{Body, Devices, Wellness}

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
