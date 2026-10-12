defmodule MilosTraining.Organizations.Commands.RenameOrganizationSlug do
  @moduledoc """
  ADR-104: vendor-only rename of an organization's path slug.

  The previous slug is kept as an `organization_slug_aliases` row so existing
  links keep working, and the rename, alias bookkeeping and audit event commit
  in one transaction. The vendor must retype the current slug.
  """
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.SlugRenamePolicy
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(context, organization_id, params, changed_at \\ DateTime.utc_now())

  def call(%PlatformContext{} = context, organization_id, params, changed_at)
      when is_binary(organization_id) and is_map(params) do
    with {:ok, slug} <- SlugRenamePolicy.requested_slug(value(params, :slug)) do
      RepoContext.run(%{user_id: context.user_id}, fn ->
        OrganizationStore.rename_organization_slug(
          organization_id,
          slug,
          value(params, :confirmation),
          context.user_id,
          changed_at
        )
      end)
    end
  end

  def call(%PlatformContext{}, _organization_id, _params, _changed_at),
    do: {:error, :invalid_slug}

  def call(_context, _organization_id, _params, _changed_at), do: {:error, :vendor_required}

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
