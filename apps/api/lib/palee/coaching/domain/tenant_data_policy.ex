defmodule Palee.Coaching.Domain.TenantDataPolicy do
  @moduledoc """
  Coaching tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "coaching",
            purge_order: 65,
            disposition: :purge,
            basis:
              "Coaching notes, form reviews, reply alerts and coach-client relationships are coaching records with no retention obligation; deleted once exported.",
            tables: [
              %{table: "coaching_note_reads"},
              %{table: "coaching_notes"},
              %{table: "coaching_form_reviews"},
              %{table: "coaching_reply_alerts"},
              %{table: "coaching_relationships"}
            ]
          })

  def policy, do: @policy
end
