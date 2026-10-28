defmodule Palee.Organizations.Commands.JoinByLink do
  @moduledoc """
  Adds the authenticated account to an organization through its public join
  link. The link names the client role (ADR-216), never the visitor.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{GoLivePolicy, JoinLinkPolicy}
  alias Palee.Organizations.OrganizationStore

  def call(%{slug: slug, role: role} = link, user_id, joined_at)
      when is_binary(slug) and is_binary(role) and is_binary(user_id) do
    RepoContext.run(%{invitation_redemption: true, user_id: user_id}, fn ->
      OrganizationStore.transaction(fn ->
        join(slug, role, Map.get(link, :key), user_id, joined_at)
      end)
    end)
  end

  def call(_link, _user_id, _joined_at), do: {:error, :join_link_unavailable}

  defp join(slug, role, key, user_id, joined_at) do
    with %{} = organization <- OrganizationStore.get_organization_by_slug(slug),
         settings <- OrganizationStore.get_organization_settings(organization.id),
         join_link <- JoinLinkPolicy.from_settings(settings && settings.settings),
         true <- JoinLinkPolicy.joinable?(join_link, role, key, organization.status),
         # ADR-184: a business in demo mode is not reachable from outside.
         :ok <- GoLivePolicy.check(organization, :join) do
      membership = OrganizationStore.get_membership(organization.id, user_id)

      case JoinLinkPolicy.join_decision(membership) do
        :already_member ->
          {:ok,
           %{
             organization: organization,
             membership: membership,
             settings: settings,
             created: false
           }}

        :create ->
          with {:ok, created} <-
                 OrganizationStore.add_membership(%{
                   organization_id: organization.id,
                   user_id: user_id,
                   role: String.to_existing_atom(role),
                   status: :active,
                   joined_at: joined_at
                 }) do
            {:ok,
             %{organization: organization, membership: created, settings: settings, created: true}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      _unavailable -> {:error, :join_link_unavailable}
    end
  end
end
