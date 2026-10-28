defmodule Palee.Organizations.Commands.UpdateJoinLink do
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{GoLivePolicy, JoinLinkPolicy, TenantAuthorization}
  alias Palee.Organizations.OrganizationStore

  def call(context, params) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
      RepoContext.run(context, fn ->
        settings = OrganizationStore.get_organization_settings(context.organization_id)
        current = JoinLinkPolicy.from_settings(settings && settings.settings)

        with {:ok, join_link} <-
               JoinLinkPolicy.update(current, params, JoinLinkPolicy.new_key()),
             :ok <- live_link(context, join_link),
             {:ok, _settings} <-
               OrganizationStore.put_organization_settings_entry(
                 context.organization_id,
                 JoinLinkPolicy.settings_key(),
                 join_link
               ) do
          {:ok, join_link}
        end
      end)
    end
  end

  # ADR-184: a business in demo mode may set its links up but not open them.
  defp live_link(context, join_links) do
    if Enum.any?(join_links, fn {_role, link} -> link["enabled"] end),
      do: GoLivePolicy.check(Map.get(context, :organization), :invite_people),
      else: :ok
  end
end
