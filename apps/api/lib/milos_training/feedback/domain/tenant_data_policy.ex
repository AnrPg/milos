defmodule MilosTraining.Feedback.Domain.TenantDataPolicy do
  @moduledoc """
  Feedback tenant data retention and purge policy (ADR-099).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

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
