defmodule MilosTraining.Organizations.Queries.FindOrganization do
  alias MilosTraining.Organizations.OrganizationStore

  def by_id(id), do: OrganizationStore.get_organization_by_id(id)
  def by_slug(slug), do: OrganizationStore.get_organization_by_slug(slug)
  def by_domain(host), do: OrganizationStore.get_organization_by_domain(host)
end
