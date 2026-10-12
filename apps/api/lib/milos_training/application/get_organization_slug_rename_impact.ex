defmodule MilosTraining.Application.GetOrganizationSlugRenameImpact do
  @moduledoc "ADR-112: impact summary a vendor reviews before confirming a slug rename."
  alias MilosTraining.Organizations

  def call(platform_context, organization_id),
    do: Organizations.slug_rename_impact(platform_context, organization_id)
end
