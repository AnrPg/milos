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

    Enum.each(report.platform_administered, fn status ->
      Mix.shell().info(
        "platform-administered #{status.table}: rls=#{status.rls_enabled} " <>
          "force=#{status.rls_forced} (exempt: holds the tenancy model itself)"
      )
    end)

    Enum.each(report.materialized_views, fn status ->
      Mix.shell().info(
        "materialized-view #{status.view}: present=#{status.present} " <>
          "(no RLS possible; relies on query-layer organization_id filtering)"
      )
    end)

    Enum.each(report.unclassified_tables, fn table ->
      Mix.shell().error("UNCLASSIFIED #{table}: has organization_id but no classification")
    end)

    Enum.each(report.legacy_fallback_policies, fn %{table: table, policy: policy} ->
      Mix.shell().error("LEGACY-FALLBACK #{table}.#{policy}: policy references the legacy org")
    end)

    unless MilosTraining.Infrastructure.Tenancy.Audit.ready_for_full_enforcement?(report) do
      Mix.raise(failure_reason(report))
    end
  end

  defp failure_reason(report) do
    [
      report.unclassified_tables != [] &&
        "unclassified tenant tables: #{Enum.join(report.unclassified_tables, ", ")}",
      report.legacy_fallback_policies != [] &&
        "policies still falling back to the legacy organization: " <>
          Enum.map_join(report.legacy_fallback_policies, ", ", &"#{&1.table}.#{&1.policy}")
    ]
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> "Tenant enforcement is incomplete; transitional contexts remain"
      reasons -> "Tenant enforcement is incomplete - " <> Enum.join(reasons, "; ")
    end
  end

  defp print_status(classification, status) do
    Mix.shell().info(
      "#{classification} #{status.table}: unmapped=#{status.unmapped_rows} " <>
        "rls=#{status.rls_enabled} force=#{status.rls_forced}"
    )
  end
end
