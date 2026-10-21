defmodule Palee.Feedback.Domain.TenantDataPolicy do
  @moduledoc """
  Feedback tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "feedback",
            purge_order: 50,
            disposition: :purge,
            basis: "Reviews and questionnaires are tenant feedback with no retention obligation.",
            tables: [
              %{table: "review_answers"},
              %{table: "reviews"},
              %{table: "review_questionnaires"}
            ]
          })

  def policy, do: @policy
end
