defmodule Mix.Tasks.Milos.Architecture do
  use Mix.Task

  @shortdoc "Fails when compile-time dependencies cross protected hexagonal boundaries"

  @application_forbidden [
    ~r/MilosTraining\.Infrastructure/,
    ~r/MilosTrainingWeb/,
    ~r/MilosTraining\.Repo/,
    ~r/(?:use|import|alias) Ecto\.(?:Schema|Query)/
  ]

  @domain_forbidden @application_forbidden ++
                      [~r/Date\.utc_today\(\)/, ~r/DateTime\.utc_now\(\)/]

  @controller_forbidden [
    ~r/MilosTraining\.Infrastructure/,
    ~r/MilosTraining\.Repo/,
    ~r/MilosTraining\.[A-Z][A-Za-z]+\.(?:Commands|Queries|Domain)\./
  ]

  @impl Mix.Task
  def run(_args) do
    violations =
      scan("lib/milos_training/application/**/*.ex", @application_forbidden, "application") ++
        scan("lib/milos_training/*/application/**/*.ex", @application_forbidden, "application") ++
        scan("lib/milos_training/*/domain/**/*.ex", @domain_forbidden, "domain") ++
        scan("lib/milos_training_web/controllers/**/*.ex", @controller_forbidden, "interface") ++
        tenant_scope_violations() ++
        materialized_view_violations()

    case violations do
      [] ->
        Mix.shell().info("Hexagonal architecture boundaries are clean")

      violations ->
        Mix.raise("Hexagonal architecture violations:\n" <> Enum.join(violations, "\n"))
    end
  end

  defp scan(pattern, forbidden, layer) do
    pattern
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      path
      |> File.stream!()
      |> Stream.with_index(1)
      |> Enum.flat_map(fn {line, line_number} ->
        if Enum.any?(forbidden, &Regex.match?(&1, line)) do
          ["  #{path}:#{line_number} [#{layer}] #{String.trim(line)}"]
        else
          []
        end
      end)
    end)
  end

  # Every context that owns tenant data must route its reads and writes through
  # a RepoContext-opened session, or its store silently runs with whatever
  # session GUCs happen to be set. F-13: this used to check Scheduling alone,
  # so the other ten contexts could drift without the task noticing.
  @tenant_scoped_stores ~w(
    scheduling/scheduling_store
    workouts/workout_store
    messaging/thread_store
    feedback/feedback_store
    analytics/analytics_store
    gamification/gamification_store
    finance/finance_store
    execution/execution_store
    wellbeing/wellbeing_store
    notifications/notification_store
    coaching/coaching_store
  )

  defp tenant_scope_violations do
    store_violations =
      Enum.reduce(@tenant_scoped_stores, [], fn store, violations ->
        path = "lib/milos_training/#{store}.ex"

        cond do
          not File.exists?(path) ->
            ["  #{path} [tenant-scope] store facade is missing" | violations]

          true ->
            require_source(
              violations,
              File.read!(path),
              "RepoContext.run",
              path,
              "tenant-scope"
            )
        end
      end)

    require_source(
      store_violations,
      File.read!("lib/milos_training/infrastructure/scheduling/ecto_scheduling_store.ex"),
      "for_organization(organization_id)",
      "lib/milos_training/infrastructure/scheduling/ecto_scheduling_store.ex",
      "tenant-predicate"
    )
  end

  # Materialized views cannot carry RLS, so their only tenant boundary is the
  # organization_id predicate in the query text itself. F-21/F-22 were exactly
  # this predicate going missing. This is the permanent guardrail the
  # retirement plan (Phase 7) asks for: any raw SQL naming one of these views
  # must also name organization_id.
  @tenant_materialized_views ~w(finance_aggregates coaching_aggregates weekly_leaderboard)

  defp materialized_view_violations do
    "lib/milos_training/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      source = File.read!(path)

      @tenant_materialized_views
      |> Enum.filter(&String.contains?(source, &1))
      |> Enum.flat_map(fn view ->
        if unscoped_view_query?(source, view) do
          ["  #{path} [materialized-view] queries #{view} without an organization_id predicate"]
        else
          []
        end
      end)
    end)
  end

  # For each line naming the view, look at the surrounding lines for the
  # organization_id predicate. A window is used rather than whole-file matching
  # so one query's predicate cannot vouch for another's.
  #
  # Exempt: REFRESH MATERIALIZED VIEW and the refresh_view/1 helper, which
  # rebuild the whole view as a platform operation and carry no row predicate.
  @view_window 8

  defp unscoped_view_query?(source, view) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, _i} -> String.contains?(line, view) end)
    |> Enum.reject(fn {line, _i} ->
      String.contains?(line, "REFRESH MATERIALIZED VIEW") or
        String.contains?(line, "refresh_view(")
    end)
    |> Enum.any?(fn {_line, i} ->
      lines
      |> Enum.slice(max(i - @view_window, 0), @view_window * 2 + 1)
      |> Enum.join("\n")
      |> then(&(not String.contains?(&1, "organization_id")))
    end)
  end

  defp require_source(violations, source, required, path, label) do
    if String.contains?(source, required),
      do: violations,
      else: ["  #{path} [#{label}] missing #{required}" | violations]
  end
end
