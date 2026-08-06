defmodule MilosTraining.Organizations.Commands.DeleteOrganization do
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context, organization_id, deleted_at)
      when is_binary(organization_id) do
    OrganizationStore.delete_organization(organization_id, context.user_id, deleted_at)
  end

  def call(%PlatformContext{}, _organization_id, _deleted_at), do: {:error, :not_found}
  def call(_context, _organization_id, _deleted_at), do: {:error, :vendor_required}
end
