defmodule MilosTraining.Media.Domain.TenantDataPolicy do
  @moduledoc """
  Media tenant data retention and purge policy (ADR-117, ADR-148). The rows
  describe objects; the objects themselves are purged by prefix with the
  tenant's other objects (`TenantObjectStorage`).
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "media",
            purge_order: 5,
            disposition: :purge,
            basis:
              "Box and post photos are gym content with no retention obligation; deleted once exported, together with their objects.",
            tables: [%{table: "media_tenant_objects"}]
          })

  def policy, do: @policy
end
