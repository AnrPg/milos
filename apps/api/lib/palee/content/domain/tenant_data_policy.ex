defmodule Palee.Content.Domain.TenantDataPolicy do
  @moduledoc """
  Content tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "content",
            purge_order: 75,
            disposition: :purge,
            basis:
              "Gym video library entries are links to externally hosted videos; no retention obligation.",
            tables: [
              %{table: "content_videos"}
            ]
          })

  def policy, do: @policy
end
