defmodule MilosTraining.Partners.Domain.TenantDataPolicy do
  @moduledoc """
  Partners tenant data retention and purge policy (ADR-117, ADR-169).

  Declares the tables this context owns, in delete (dependency) order.
  Purged before Community (profiles, swipes and matches reference the
  gym's clubs).
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "partners",
            purge_order: 12,
            disposition: :purge,
            basis:
              "Partners profiles, swipes, matches and their conversations are social data of the gym's club members with no retention obligation; deleted once exported.",
            tables: [
              %{table: "partner_messages"},
              %{table: "partner_matches"},
              %{table: "partner_swipes"},
              %{table: "partner_profiles"}
            ]
          })

  def policy, do: @policy
end
