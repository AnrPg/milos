defmodule Palee.Organizations.Commands.OwnerOrganizationActions do
  @moduledoc """
  What only a gym's owner does (ADR-099): create another gym (they become its
  owner), hand ownership to another member, and archive the gym. Archiving
  closes the gym to everyone; the vendor deletes it for good.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Commands.SeedTenantDefaults
  alias Palee.Organizations.Domain.{GoLivePolicy, TenantAuthorization}
  alias Palee.Organizations.OrganizationStore

  @doc """
  An account that owns a gym creates another one and owns it. The gym, its
  settings, the owner membership and `opts[:seed_defaults]` (run in the new
  gym's tenant scope) commit or roll back together (ADR-133).
  """
  def create(%{id: user_id}, params, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    seed_defaults = SeedTenantDefaults.seed_option(opts)

    case owned_gyms(user_id) do
      :none -> {:error, :owner_required}
      # ADR-184: a verified (activated) owner opens more gyms; an owner whose
      # only businesses are still in demo mode waits for activation.
      :demo_only -> {:error, :business_not_activated}
      :active -> create_gym(user_id, params, now, seed_defaults)
    end
  end

  defp create_gym(user_id, params, now, seed_defaults) do
    # The organization row is written as a system insert: its RLS policy only
    # admits members of the row (none exist yet) or a session without a user.
    # The caller was authorized above; the owner membership is then written
    # in the new organization's scope.
    OrganizationStore.transaction(fn ->
      with {:ok, organization} <-
             OrganizationStore.create_organization(%{name: params["name"] || params[:name]}),
           {:ok, _membership} <-
             RepoContext.run(%{organization_id: organization.id, user_id: user_id}, fn ->
               OrganizationStore.add_membership(%{
                 organization_id: organization.id,
                 user_id: user_id,
                 role: :owner,
                 roles: [:owner],
                 status: :active,
                 joined_at: now
               })
             end),
           {:ok, _defaults} <- SeedTenantDefaults.run(organization.id, user_id, seed_defaults) do
        {:ok, organization}
      end
    end)
  end

  @doc "The owner hands ownership to an active member and stays as admin."
  def transfer(context, to_user_id) do
    with :ok <- TenantAuthorization.authorize_capability(context, :manage_organization_lifecycle) do
      RepoContext.run(context, fn -> transfer_ownership(context, to_user_id) end)
    end
  end

  defp transfer_ownership(context, to_user_id) do
    with true <- to_user_id != context.user_id || {:error, :cannot_change_own_membership},
         %{status: :active} = target <-
           OrganizationStore.get_membership(context.organization_id, to_user_id) ||
             {:error, :not_found},
         %{} = own <- OrganizationStore.get_membership(context.organization_id, context.user_id) do
      OrganizationStore.transaction(fn ->
        with {:ok, new_owner} <-
               OrganizationStore.update_membership_roles(
                 context.organization_id,
                 target.id,
                 Enum.uniq([:owner | target.roles])
               ),
             {:ok, _former} <-
               OrganizationStore.update_membership_roles(
                 context.organization_id,
                 own.id,
                 Enum.uniq([:admin | own.roles -- [:owner]])
               ) do
          {:ok, new_owner}
        end
      end)
    end
  end

  @doc "Archives the gym; `confirm` must repeat its slug."
  def archive(context, confirm) do
    with :ok <- TenantAuthorization.authorize_capability(context, :manage_organization_lifecycle),
         true <- confirm == context.organization.slug || {:error, :confirmation_mismatch} do
      RepoContext.run(context, fn ->
        OrganizationStore.set_organization_status(context.organization_id, :archived)
      end)
    end
  end

  defp owned_gyms(user_id) do
    owned =
      RepoContext.run(%{user_id: user_id}, fn ->
        user_id
        |> OrganizationStore.list_memberships()
        |> Enum.filter(&(:owner in &1.membership.roles))
        |> Enum.map(& &1.organization)
      end)

    cond do
      owned == [] -> :none
      Enum.all?(owned, &GoLivePolicy.gated?/1) -> :demo_only
      true -> :active
    end
  end
end
