defmodule Palee.Application.ResolveOrganizationSlugAlias do
  @moduledoc "ADR-122: retired slug -> canonical slug, for the web proxy's 308 redirect."
  alias Palee.Organizations

  def call(slug), do: Organizations.resolve_slug_alias(slug)
end
