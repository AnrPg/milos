defmodule Mix.Tasks.Milos.Storage.MigrateLegacyObjects do
  use Mix.Task

  alias MilosTraining.Infrastructure.Storage.LegacyObjectMigration

  @shortdoc "Migrates legacy invoice/avatar object keys into tenant/user prefixes"

  @moduledoc """
  Migrates pre-tenancy MinIO keys into canonical ownership prefixes.

      mix milos.storage.migrate_legacy_objects
      mix milos.storage.migrate_legacy_objects --apply
      mix milos.storage.migrate_legacy_objects --apply --delete-legacy

  The task is dry-run by default. `--apply` copies and verifies objects before
  updating PostgreSQL. `--delete-legacy` removes the old object only after the
  canonical object is verified and the persisted reference has been updated.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {options, _argv, invalid} =
      OptionParser.parse(args,
        strict: [apply: :boolean, delete_legacy: :boolean, limit: :integer],
        aliases: [a: :apply]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    report =
      LegacyObjectMigration.run(
        apply: Keyword.get(options, :apply, false),
        delete_legacy: Keyword.get(options, :delete_legacy, false),
        limit: Keyword.get(options, :limit)
      )

    Mix.shell().info(
      "legacy-object-migration apply=#{report.apply?} delete_legacy=#{report.delete_legacy?} " <>
        "scanned=#{report.scanned} planned=#{report.planned} migrated=#{report.migrated} " <>
        "warnings=#{report.migrated_with_warnings} skipped=#{report.skipped} failed=#{report.failed}"
    )

    Enum.each(report.results, &print_result/1)

    if report.failed > 0 do
      Mix.raise("Legacy object migration finished with #{report.failed} failure(s)")
    end
  end

  defp print_result({:planned, item}), do: print_item("planned", item)
  defp print_result({:migrated, item}), do: print_item("migrated", item)
  defp print_result({:skipped, item, reason}), do: print_item("skipped:#{inspect(reason)}", item)

  defp print_result({:migrated_with_warnings, item, warning}),
    do: print_item("migrated-warning:#{inspect(warning)}", item)

  defp print_result({:error, item, reason}), do: print_item("failed:#{inspect(reason)}", item)

  defp print_item(status, item) do
    Mix.shell().info(
      "#{status} #{item.kind} #{item.record.id} #{item.source_bucket}/#{item.source_key} -> " <>
        "#{item.destination_bucket}/#{item.destination_key}"
    )
  end
end
