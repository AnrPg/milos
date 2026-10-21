defmodule Palee.Repo.Migrations.JournalCommentsCoachSharedRead do
  @moduledoc """
  ADR-162: a comment follows its entry. An entry the member shared with
  another provider («Οι coach μου», `palee_entry_shared_with_acting_coach`)
  carries its comments to that provider's coaches, on the entry's own rung.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE POLICY journal_comments_coach_shared_read_policy ON journal_comments
    FOR SELECT
    USING (
      deleted_at IS NULL
      AND palee_entry_shared_with_acting_coach(
        entry_kind, entry_id, user_id, organization_id,
        palee_journal_entry_rung(entry_kind, entry_id)
      )
    )
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS journal_comments_coach_shared_read_policy ON journal_comments")
  end
end
