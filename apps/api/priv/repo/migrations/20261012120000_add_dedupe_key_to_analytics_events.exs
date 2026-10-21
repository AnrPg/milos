defmodule Palee.Repo.Migrations.AddDedupeKeyToAnalyticsEvents do
  use Ecto.Migration

  # ADR-123 / TD-011: analytics events that must be recorded at most once
  # (assignment opened per user/assignment/day, execution abandoned once per
  # execution, client-batched execution interactions keyed by a client event
  # id, thread created once per thread) carry a `dedupe_key`. Uniqueness is
  # per tenant and event name so two tenants (or two event families) can never
  # collide. Rows without a key (every pre-existing event) are unaffected.
  #
  # Additive only: a nullable column plus a partial unique index. The event
  # name allowlist stays in the Analytics domain registry rather than a DB
  # check constraint so new event types never need a migration.
  def change do
    alter table(:analytics_events) do
      add :dedupe_key, :string
    end

    create unique_index(:analytics_events, [:organization_id, :event_name, :dedupe_key],
             where: "dedupe_key IS NOT NULL",
             name: :analytics_events_dedupe_key_index
           )
  end
end
