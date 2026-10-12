defmodule MilosTraining.Notifications.Domain.TenantDataPolicy do
  @moduledoc """
  Notifications tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "notifications",
            purge_order: 20,
            disposition: :purge,
            basis: "In-app notifications are operational messages with no retention obligation.",
            tables: [
              %{table: "notifications", rls: :user}
            ]
          })

  def policy, do: @policy
end
