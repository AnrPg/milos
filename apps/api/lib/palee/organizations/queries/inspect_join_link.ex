defmodule Palee.Organizations.Queries.InspectJoinLink do
  @moduledoc """
  Public lookup behind `/join/<slug>` (member link) and
  `/join/<slug>/athlete/<key>` (athlete link, ADR-216). Answers the same
  `:join_link_unavailable` for unknown slugs, inactive organizations, disabled
  links and wrong keys, so it cannot be used to probe which organizations
  exist or which keys are right.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{GoLivePolicy, JoinLinkPolicy}
  alias Palee.Organizations.OrganizationStore

  def call(slug, role, key \\ nil)

  def call(slug, role, key) when is_binary(slug) and is_binary(role) do
    # The visitor is not a member yet: same carve-out as invitation inspection.
    RepoContext.run(%{invitation_redemption: true}, fn ->
      with %{} = organization <- OrganizationStore.get_organization_by_slug(slug),
           settings <- OrganizationStore.get_organization_settings(organization.id),
           join_link <- JoinLinkPolicy.from_settings(settings && settings.settings),
           true <- JoinLinkPolicy.joinable?(join_link, role, key, organization.status),
           # ADR-184: a business in demo mode is not reachable from outside.
           :ok <- GoLivePolicy.check(organization, :join) do
        {:ok, %{organization: organization, settings: settings, role: role}}
      else
        _unavailable -> {:error, :join_link_unavailable}
      end
    end)
  end

  def call(_slug, _role, _key), do: {:error, :join_link_unavailable}
end
