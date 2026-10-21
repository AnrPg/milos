defmodule Palee.Application.GetAccountVault do
  @moduledoc """
  `GET /api/me/vault` (ADR-162; board 17, Q4): one Vault across providers.
  The same workout done at different providers (Fran at the box and Fran
  with the coach) is one trend, grouped by its canonical identity
  (`WorkoutIdentity`); every attempt is labelled with its source. Filters
  (`VaultFilter`): discipline, benchmark, exercise, source and dates.
  `/api/executions/vault` keeps its per-workout shape.
  """

  alias Palee.Application.AccountTraining
  alias Palee.Execution

  def call(context, params) do
    with {:ok, filter} <- Execution.parse_vault_filter(params) do
      groups =
        context
        |> AccountTraining.load()
        |> AccountTraining.attempts()
        |> Enum.filter(&Execution.vault_attempt_matches?(filter, &1))
        |> Enum.group_by(& &1.key)
        |> Enum.map(&group/1)
        |> Enum.sort_by(& &1.last_at, {:desc, DateTime})

      {:ok,
       %{
         groups: groups,
         filter: Execution.vault_filter_params(filter),
         active_filter_count: Execution.vault_filter_active_count(filter)
       }}
    end
  end

  defp group({key, attempts}) do
    [latest | _older] = attempts = Enum.sort_by(attempts, & &1.at, {:desc, DateTime})
    benchmark = Execution.identity_benchmark(key)

    %{
      identity: key,
      benchmark: benchmark,
      title: if(benchmark, do: Execution.benchmark_name(benchmark), else: latest.title),
      workout_type: latest.type,
      attempt_count: length(attempts),
      last_at: latest.at,
      sources: attempts |> Enum.map(& &1.source) |> Enum.uniq(),
      attempts: Enum.map(attempts, &Map.drop(&1, [:key, :exercise_names, :source_token]))
    }
  end
end
