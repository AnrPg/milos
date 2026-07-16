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
        scan("lib/milos_training_web/controllers/**/*.ex", @controller_forbidden, "interface")

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
end
