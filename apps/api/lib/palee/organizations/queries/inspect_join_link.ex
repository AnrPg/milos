defmodule Palee.Organizations.Queries.InspectJoinLink do
  @moduledoc """
  Public lookup behind `/join/<slug>`. Answers the same `:join_link_unavailable`
  for unknown slugs, inactive organizations and disabled links, so it cannot
  be used to probe which organizations exist.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.JoinLinkPolicy
  alias Palee.Organizations.OrganizationStore

  def call(slug) when is_binary(slug) do
    # The visitor is not a member yet: same carve-out as invitation inspection.
    RepoContext.run(%{invitation_redemption: true}, fn ->
      with %{} = organization <- OrganizationStore.get_organization_by_slug(slug),
           settings <- OrganizationStore.get_organization_settings(organization.id),
           join_link <- JoinLinkPolicy.from_settings(settings && settings.settings),
           true <- JoinLinkPolicy.joinable?(join_link, organization.status) do
        {:ok, %{organization: organization, settings: settings, role: join_link["role"]}}
      else
        _unavailable -> {:error, :join_link_unavailable}
      end
    end)
  end

  def call(_slug), do: {:error, :join_link_unavailable}
end
