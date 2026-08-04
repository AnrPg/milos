defmodule Mix.Tasks.Milos.Tenancy.Audit do
  use Mix.Task

  @shortdoc "Reports tenant ownership and RLS enforcement readiness"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    report = MilosTraining.Infrastructure.Tenancy.Audit.report()

    Enum.each(report.ready, &print_status("ready", &1))
    Enum.each(report.ready_personal, &print_status("ready-personal", &1))
    Enum.each(report.transitional, &print_status("transitional", &1))

    unless MilosTraining.Infrastructure.Tenancy.Audit.ready_for_full_enforcement?(report) do
      Mix.raise("Tenant enforcement is incomplete; transitional contexts remain")
    end
  end

  defp print_status(classification, status) do
    Mix.shell().info(
      "#{classification} #{status.table}: unmapped=#{status.unmapped_rows} " <>
        "rls=#{status.rls_enabled} force=#{status.rls_forced}"
    )
  end
end
