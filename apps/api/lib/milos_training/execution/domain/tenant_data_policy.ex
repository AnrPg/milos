defmodule MilosTraining.Execution.Domain.TenantDataPolicy do
  @moduledoc """
  Execution tenant data retention and purge policy (ADR-099).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "execution",
            purge_order: 30,
            disposition: :purge,
            basis:
              "Workout execution logs are member training data with no retention obligation once the tenant is offboarded.",
            tables: [
              %{
                table: "execution_progress_operations",
                parent: {"workout_executions", "execution_id"},
                rls: :user
              },
              %{table: "workout_executions"}
            ]
          })

  def policy, do: @policy
end
