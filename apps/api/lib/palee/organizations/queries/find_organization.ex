defmodule Palee.Organizations.Queries.FindOrganization do
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.OrganizationStore

  # Looking an organization up by id is how server-side code (jobs, system
  # tenant resolution) enters a tenant, so it reads inside that organization's
  # own scope; RLS admits the row through the scoped self-read policy (TD-046).
  def by_id(id) when is_binary(id),
    do:
      RepoContext.run(%{organization_id: id}, fn ->
        OrganizationStore.get_organization_by_id(id)
      end)

  def by_id(_id), do: nil

  # TD-092: same scoped self-read for the organization's settings row (brand
  # name, locale), e.g. for server-side email senders.
  def settings_by_id(id) when is_binary(id),
    do:
      RepoContext.run(%{organization_id: id}, fn ->
        OrganizationStore.get_organization_settings(id)
      end)

  def settings_by_id(_id), do: nil

  def by_slug(slug), do: OrganizationStore.get_organization_by_slug(slug)
  def by_domain(host), do: OrganizationStore.get_organization_by_domain(host)
end
