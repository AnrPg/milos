defmodule MilosTraining.Application.RenameOrganizationSlug do
  @moduledoc "ADR-112: vendor slug rename with retired-slug alias and typed confirmation."
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, params),
    do: Organizations.rename_organization_slug(platform_context, organization_id, params)
end
