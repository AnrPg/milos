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
        tenant_scope_violations()

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

  defp require_source(violations, source, required, path, label) do
    if String.contains?(source, required),
      do: violations,
      else: ["  #{path} [#{label}] missing #{required}" | violations]
  end
end
