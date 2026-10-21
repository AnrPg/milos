defmodule MilosTraining.Journal.Domain.TenantDataPolicy do
  @moduledoc """
  Journal tenant data retention and purge policy (ADR-117, ADR-139).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "journal",
            purge_order: 45,
            disposition: :purge,
            basis:
              "Journal notes are member-written personal data; coach-read audit rows and the member's per-provider coach audiences (ADR-162) only matter while the gym exists.",
            tables: [
              %{table: "journal_entry_audiences", rls: :user},
              %{table: "journal_coach_audience_exclusions", rls: :user},
              %{table: "journal_coach_reads"},
              %{table: "journal_comments", rls: :user},
              %{table: "journal_notes", rls: :user}
            ]
          })

  def policy, do: @policy
end
