defmodule Palee.Execution.Domain.TenantDataPolicy do
  @moduledoc """
  Execution tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "execution",
            purge_order: 30,
            disposition: :purge,
            basis:
              "Workout execution and training-log entries are member training data with no retention obligation once the tenant is offboarded.",
            tables: [
              %{
                table: "execution_progress_operations",
                parent: {"workout_executions", "execution_id"},
                rls: :user
              },
              %{table: "workout_executions"},
              # ADR-118 standalone training-log entries; their RLS USING clause
              # admits organization sessions, so purge runs per tenant.
              %{table: "training_log_entries"},
              # Coach-run class timers (one per scheduled class), RLS by organization.
              %{table: "class_timers"}
            ]
          })

  def policy, do: @policy
end
