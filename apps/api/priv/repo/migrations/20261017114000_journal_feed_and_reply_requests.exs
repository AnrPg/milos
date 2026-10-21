defmodule Palee.Repo.Migrations.JournalFeedAndReplyRequests do
  @moduledoc """
  ADR-139 read side (M5.4).

  * Reviews (and their answers) are tenant-scoped rows, but they are also the
    member's own journal entries (the `rated` rung): owner read policies let
    the personal journal feed list them across gyms.
  * Messages about a journal entry (Ζητάω απάντηση, ADR-139 §7) are found by
    their subject.
  * The feed pages injuries by report time.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE POLICY reviews_owner_read_policy ON reviews
    FOR SELECT
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("""
    CREATE POLICY review_answers_owner_read_policy ON review_answers
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM reviews review
        WHERE review.id = review_answers.review_id
          AND review.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      )
    )
    """)

    create index(:messaging_messages, [:subject_kind, :subject_id],
             where: "subject_id IS NOT NULL"
           )

    create index(:injury_reports, [:user_id, :inserted_at])
  end

  def down do
    drop index(:injury_reports, [:user_id, :inserted_at])
    drop index(:messaging_messages, [:subject_kind, :subject_id])
    execute("DROP POLICY IF EXISTS review_answers_owner_read_policy ON review_answers")
    execute("DROP POLICY IF EXISTS reviews_owner_read_policy ON reviews")
  end
end
