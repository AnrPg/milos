defmodule Palee.Setup.Domain.TenantDataPolicy do
  @moduledoc """
  Setup tenant data retention and purge policy (ADR-117, ADR-255).

  The record of applied setup recipes is operational history of how the
  business was configured; the configuration itself lives in the contexts
  that own it. Deleted once exported.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "setup",
            purge_order: 6,
            disposition: :purge,
            basis:
              "Setup recipe applications record which starting configuration an owner applied and when; the settings, packages and class types they created belong to their own contexts, so the record is deleted once exported.",
            tables: [%{table: "setup_recipe_applications"}]
          })

  def policy, do: @policy
end
