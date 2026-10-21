defmodule Palee.Organizations.Commands.JoinByLink do
  @moduledoc """
  Adds the authenticated account to an organization through its public join
  link, with the client role the organization configured.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.JoinLinkPolicy
  alias Palee.Organizations.OrganizationStore

  def call(slug, user_id, joined_at) when is_binary(slug) and is_binary(user_id) do
    RepoContext.run(%{invitation_redemption: true, user_id: user_id}, fn ->
      OrganizationStore.transaction(fn -> join(slug, user_id, joined_at) end)
    end)
  end

  def call(_slug, _user_id, _joined_at), do: {:error, :join_link_unavailable}

  defp join(slug, user_id, joined_at) do
    with %{} = organization <- OrganizationStore.get_organization_by_slug(slug),
         settings <- OrganizationStore.get_organization_settings(organization.id),
         join_link <- JoinLinkPolicy.from_settings(settings && settings.settings),
         true <- JoinLinkPolicy.joinable?(join_link, organization.status) do
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
                   role: String.to_existing_atom(join_link["role"]),
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
