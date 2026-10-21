defmodule Palee.Repo.Migrations.PhoneHealth do
  @moduledoc """
  ADR-172: Apple Health and Health Connect send what the phone reads through
  the same Devices tables as Garmin (ADR-161).

  - `daily_stats.steps`: a day's step count from the phone, next to the
    resting heart rate, one row per person, day and source.
  - `device_imports.kind` gains `steps` (a day's steps is its own import, so
    its sync choice and dedupe work like the other kinds).
  - `body_snapshots.source` accepts the two phone providers, as wellness
    entries and daily stats already do.

  Every table keeps its owner-only row security; nothing new is shared.
  """

  use Ecto.Migration

  def up do
    alter table(:daily_stats) do
      add :steps, :integer
    end

    create constraint(:daily_stats, :daily_stats_steps_check,
             check: "steps IS NULL OR steps BETWEEN 0 AND 200000"
           )

    replace_check(
      :device_imports,
      :device_imports_kind_check,
      "kind IN ('activity', 'sleep', 'weight', 'daily', 'steps')"
    )

    replace_check(
      :body_snapshots,
      :body_snapshots_source_check,
      "source IN ('manual', 'garmin', 'apple_health', 'health_connect')"
    )
  end

  def down do
    execute("DELETE FROM device_imports WHERE kind = 'steps'")

    execute(
      "UPDATE body_snapshots SET source = 'manual' WHERE source IN ('apple_health', 'health_connect')"
    )

    replace_check(
      :body_snapshots,
      :body_snapshots_source_check,
      "source IN ('manual', 'garmin')"
    )

    replace_check(
      :device_imports,
      :device_imports_kind_check,
      "kind IN ('activity', 'sleep', 'weight', 'daily')"
    )

    drop constraint(:daily_stats, :daily_stats_steps_check)

    alter table(:daily_stats) do
      remove :steps
    end
  end

  defp replace_check(table, name, check) do
    drop constraint(table, name)
    create constraint(table, name, check: check)
  end
end
