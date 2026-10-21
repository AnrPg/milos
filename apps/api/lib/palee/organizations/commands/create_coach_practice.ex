defmodule Palee.Organizations.Commands.CreateCoachPractice do
  @moduledoc """
  ADR-170: any account opens its own practice as an independent coach (vision
  §7.10): a one-person organization of kind `coach`, owned by the account,
  who is also its coach. The organization, its settings, the membership and
  `opts[:seed_defaults]` (the tenant defaults, the team club and the plan)
  commit or roll back together (ADR-133).

  One practice per account: a second one is refused while the first is
  active, so self-serve sign-up cannot be used to spray organizations.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Commands.SeedTenantDefaults
  alias Palee.Organizations.Domain.OrganizationPolicy
  alias Palee.Organizations.OrganizationStore

  @kind "coach"

  def call(%{id: user_id}, params, opts \\ []) when is_binary(user_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    seed_defaults = SeedTenantDefaults.seed_option(opts)

    if owns_a_practice?(user_id) do
      {:error, :coach_practice_exists}
    else
      OrganizationStore.transaction(fn ->
        with {:ok, organization} <-
               OrganizationStore.create_organization(organization_params(params)),
             {:ok, _membership} <-
               RepoContext.run(%{organization_id: organization.id, user_id: user_id}, fn ->
                 OrganizationStore.add_membership(%{
                   organization_id: organization.id,
                   user_id: user_id,
                   role: :owner,
                   roles: [:owner, :coach],
                   coach_scope: :all,
                   status: :active,
                   joined_at: now
                 })
               end),
             {:ok, _defaults} <- SeedTenantDefaults.run(organization.id, user_id, seed_defaults) do
          {:ok, organization}
        end
      end)
    end
  end

  defp organization_params(params) do
    %{
      name: value(params, :name),
      provider_kind: @kind,
      slug: free_slug(value(params, :name)),
      timezone: value(params, :timezone),
      default_locale: value(params, :default_locale)
    }
  end

  # The practice's own slug, else a numbered one, else a random suffix (the
  # unique index still settles a race).
  defp free_slug(name) do
    candidates = OrganizationPolicy.slug_candidates(name || "", "coach")

    Enum.find(candidates, &(not OrganizationStore.slug_taken?(&1))) ||
      "#{hd(candidates)}-#{:crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)}"
  end

  defp owns_a_practice?(user_id) do
    RepoContext.run(%{user_id: user_id}, fn ->
      user_id
      |> OrganizationStore.list_memberships()
      |> Enum.any?(fn %{membership: membership, organization: organization} ->
        :owner in membership.roles and organization.provider_kind == @kind
      end)
    end)
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
