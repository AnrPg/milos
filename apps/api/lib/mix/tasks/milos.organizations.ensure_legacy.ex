defmodule Mix.Tasks.Milos.Organizations.EnsureLegacy do
  use Mix.Task

  @shortdoc "Idempotently creates the stable legacy organization"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case MilosTraining.Organizations.ensure_legacy_organization() do
      {:ok, organization} ->
        Mix.shell().info("Legacy organization ready: #{organization.slug} (#{organization.id})")

      {:error, reason} ->
        Mix.raise("Could not create legacy organization: #{inspect(reason)}")
    end
  end
end
