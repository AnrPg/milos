defmodule MilosTraining.Application.GetAccountProgress do
  @moduledoc """
  `GET /api/me/progress` (ADR-150, ADR-162; board 17, Q4): Πρόοδος across
  every provider, «Όλοι» by default. The same sections the per-provider page
  returns (`ProgressStats`: totals, weekly, consistency, sources, score
  history, PR timeline), built from every completed workout of the account,
  with score history grouped by canonical workout identity so one benchmark
  done at two providers is one line. Points and PRs carry their source;
  `by_source` counts sessions per source.

  Filters (`ProgressFilter`): `range`, `sources`, `exercise`. The
  per-provider page stays gated by its package (ADR-098); this account view
  is the member's own data across providers and is not, like PRs.
  """

  alias MilosTraining.Application.AccountTraining
  alias MilosTraining.{Analytics, Execution, Journal, Pantheon}
  alias MilosTraining.Analytics.Domain.ProgressStats

  def call(context, params, today \\ Date.utc_today()) do
    with {:ok, filter} <- Analytics.parse_progress_filter(params) do
      loaded = AccountTraining.load(context)
      since = Analytics.progress_since(filter, today)

      executions =
        loaded.executions
        |> Enum.filter(&source?(filter.sources, &1.source_label))
        |> Enum.filter(&in_range?(&1, since))
        |> Enum.filter(
          &Execution.exercise_matches?(filter.exercise, Map.get(&1, :exercise_names))
        )

      labels = Map.new(executions, &{&1.id, &1.source_label})

      stats =
        executions
        |> Enum.map(&Map.put(&1, :master_workout_id, &1.workout_key))
        |> ProgressStats.build(today)

      {:ok,
       stats
       |> Map.update!(:score_history, &label_points(&1, labels))
       |> Map.put(:by_source, by_source(executions))
       |> Map.put(:pr_timeline, pr_timeline(context, loaded.directory, filter, since))
       |> Map.put(:filter, Analytics.progress_filter_params(filter))
       |> Map.put(:active_filter_count, Analytics.progress_filter_active_count(filter))}
    end
  end

  defp label_points(history, labels) do
    Enum.map(history, fn line ->
      Map.update!(line, :points, fn points ->
        Enum.map(points, &Map.put(&1, :source, Map.get(labels, &1.execution_id)))
      end)
    end)
  end

  defp by_source(executions) do
    executions
    |> Enum.filter(&(&1.status == "completed" and &1.completed_at_utc))
    |> Enum.frequencies_by(& &1.source_label)
    |> Enum.map(fn {source, sessions} -> %{source: source, sessions: sessions} end)
    |> Enum.sort_by(&{-&1.sessions, &1.source.name || ""})
  end

  # PRs are the member's own across providers (ADR-129); each keeps the
  # provider it was set at.
  defp pr_timeline(%{user_id: user_id} = context, directory, filter, since) do
    Pantheon.with_user_context(context, fn ->
      records = Pantheon.list_records(user_id)
      origin = Map.new(records, &{&1.id, &1.organization_id})

      records
      |> then(&ProgressStats.pr_timeline(Pantheon.list_user_record_history(user_id), &1))
      |> Enum.map(fn entry ->
        Map.put(
          entry,
          :source,
          Journal.entry_source(Map.get(origin, entry.pr_record_id), nil, directory)
        )
      end)
      |> Enum.filter(&source?(filter.sources, &1.source))
      |> Enum.filter(&Execution.exercise_matches?(filter.exercise, [&1.name]))
      |> Enum.filter(&on_or_after?(&1.beaten_on, since))
    end)
  end

  defp source?([], _label), do: true
  defp source?(sources, label), do: AccountTraining.token(label) in sources

  defp in_range?(_execution, nil), do: true

  defp in_range?(execution, since) do
    at = execution.completed_at_utc || execution.started_at_utc
    at != nil and Date.compare(DateTime.to_date(at), since) != :lt
  end

  defp on_or_after?(_on, nil), do: true
  defp on_or_after?(nil, _since), do: false

  defp on_or_after?(on, since) do
    on = if is_binary(on), do: Date.from_iso8601!(on), else: on
    Date.compare(on, since) != :lt
  end
end
