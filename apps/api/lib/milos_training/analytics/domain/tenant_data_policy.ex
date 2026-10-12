defmodule MilosTraining.Analytics.Domain.TenantDataPolicy do
  @moduledoc """
  Analytics tenant data retention and purge policy (ADR-099).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "analytics",
            purge_order: 10,
            disposition: :retain_anonymized,
            retain_years: 2,
            basis:
              "Aggregate service-usage events are kept for two years without personal identifiers; attendance, communication and delivery logs are purged.",
            retained_tables: ["analytics_events"],
            anonymized_columns: ["user_id", "context_id", "metadata"],
            tables: [
              %{table: "attendance_records"},
              %{table: "communication_messages"},
              %{table: "communication_threads"},
              %{table: "notification_click_events"},
              %{table: "push_dispatch_attempts"},
              %{table: "analytics_events"}
            ]
          })

  def policy, do: @policy
end
