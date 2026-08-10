defmodule MilosTraining.Organizations.Commands.RenameOrganization do
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context, organization_id, name) when is_binary(name) do
    OrganizationStore.rename_organization(
      organization_id,
      name,
      context.user_id,
      DateTime.utc_now()
    )
  end

  def call(%PlatformContext{}, _organization_id, _name), do: {:error, :invalid_name}
  def call(_context, _organization_id, _name), do: {:error, :vendor_required}
end
