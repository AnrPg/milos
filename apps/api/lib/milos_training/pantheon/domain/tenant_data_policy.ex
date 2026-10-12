defmodule MilosTraining.Pantheon.Domain.TenantDataPolicy do
  @moduledoc """
  Pantheon tenant data retention and purge policy (ADR-099).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "pantheon",
            purge_order: 40,
            disposition: :purge,
            basis: "Personal records are member training data with no retention obligation.",
            tables: [
              %{table: "user_pr_history", rls: {:user_via, "user_pr_records", "pr_record_id"}},
              %{table: "user_pr_records", rls: :user}
            ]
          })

  def policy, do: @policy
end
