defmodule Palee.Repo.Migrations.CrossOrgJournalRowIds do
  @moduledoc """
  ADR-162 / ADR-117: the tenant data export and purge address rows by `id`,
  so the member's per-provider rows get one beside their natural keys.
  """

  use Ecto.Migration

  @tables ~w(account_provider_selections journal_coach_audience_exclusions journal_entry_audiences)

  def change do
    for table <- @tables do
      alter table(table) do
        add :id, :binary_id, null: false, default: fragment("gen_random_uuid()")
      end

      create unique_index(table, [:id])
    end
  end
end
