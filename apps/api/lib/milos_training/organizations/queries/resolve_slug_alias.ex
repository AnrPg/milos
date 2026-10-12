defmodule MilosTraining.Organizations.Queries.ResolveSlugAlias do
  @moduledoc """
  ADR-122: maps a retired organization slug to the organization's current
  canonical slug, for the web proxy's `/org/<old>/...` 308 redirect.

  Unauthenticated by design (the proxy has no session), so it answers only for
  retired aliases and returns nothing else about the organization. Path slugs
  identify a context but never grant access (ADR-058).
  """
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.OrganizationPolicy
  alias MilosTraining.Organizations.OrganizationStore

  def call(slug) when is_binary(slug) do
    if OrganizationPolicy.valid_slug?(slug) do
      RepoContext.run(%{slug_alias_lookup: true}, fn ->
        case OrganizationStore.get_canonical_slug_for_alias(slug) do
          nil -> {:error, :not_found}
          canonical_slug -> {:ok, canonical_slug}
        end
      end)
    else
      {:error, :not_found}
    end
  end

  def call(_slug), do: {:error, :not_found}
end
