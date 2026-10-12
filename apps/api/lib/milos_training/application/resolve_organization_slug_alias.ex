defmodule MilosTraining.Application.ResolveOrganizationSlugAlias do
  @moduledoc "ADR-104: retired slug -> canonical slug, for the web proxy's 308 redirect."
  alias MilosTraining.Organizations

  def call(slug), do: Organizations.resolve_slug_alias(slug)
end
