defmodule MilosTraining.Organizations.Commands.UpdateOrganizationSettings do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  @allowed_fields %{
    "timezone" => :timezone,
    "default_locale" => :default_locale,
    "invitation_lifetime_seconds" => :invitation_lifetime_seconds,
    "brand_name" => :brand_name,
    "brand_logo_url" => :brand_logo_url,
    "brand_primary_color" => :brand_primary_color,
    "settings" => :settings
  }

  def call(%PlatformContext{} = context, organization_id, params, changed_at) do
    sanitized = sanitize(params)

    RepoContext.run(%{user_id: context.user_id}, fn ->
      OrganizationStore.update_organization_settings(
        organization_id,
        sanitized,
        context.user_id,
        changed_at
      )
    end)
  end

  def call(_context, _organization_id, _params, _changed_at),
    do: {:error, :vendor_required}

  defp sanitize(params) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      case allowed_field(key) do
        nil -> acc
        field -> Map.put(acc, field, value)
      end
    end)
  end

  defp sanitize(_params), do: %{}

  defp allowed_field(key) when is_atom(key) do
    if key in Map.values(@allowed_fields), do: key
  end

  defp allowed_field(key) when is_binary(key), do: Map.get(@allowed_fields, key)
  defp allowed_field(_key), do: nil
end
