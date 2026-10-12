defmodule MilosTraining.Organizations.Commands.ReplaceOrganizationLogo do
  @moduledoc """
  ADR-111: records a validated uploaded logo (`%{object_key, url}`) or removes
  the current one (nil) for an organization, with its audit event.

  Callers are tenant owners/admins (their own organization) and vendors
  (any organization). Storage validation happens before this command; the
  key is re-checked here so the settings row can never point outside the
  organization's logo prefix.
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.BrandLogoPolicy
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(context, organization_id, logo, changed_at) do
    with {:ok, actor} <- BrandLogoPolicy.authorize(context, organization_id),
         :ok <- validate_logo(actor.organization_id, logo) do
      RepoContext.run(repo_scope(context), fn ->
        OrganizationStore.replace_organization_logo(
          actor.organization_id,
          logo,
          %{user_id: actor.user_id, scope: actor.scope},
          changed_at
        )
      end)
    end
  end

  defp validate_logo(_organization_id, nil), do: :ok

  defp validate_logo(organization_id, %{object_key: key, url: url}) when is_binary(url) do
    if BrandLogoPolicy.owned_key?(organization_id, key),
      do: :ok,
      else: {:error, :brand_logo_key_forbidden}
  end

  defp validate_logo(_organization_id, _logo), do: {:error, :invalid_brand_logo_upload}

  @doc false
  def repo_scope(%PlatformContext{user_id: user_id}), do: %{user_id: user_id}
  def repo_scope(context), do: context
end
