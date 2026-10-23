defmodule Palee.Organizations.Commands.CreateBusinessAccount do
  @moduledoc """
  ADR-184 (generalising ADR-170's coach practice): an account opens its own
  business, a gym or an independent coach's practice, **in demo mode**. The
  organization, its settings, the owner membership and
  `opts[:seed_defaults]` commit or roll back together (ADR-133).

  - `gym`: the account is the owner.
  - `coach`: the account is owner and coach of a one-person practice.

  An account holds at most one business still in demo mode, and at most one
  coach practice at all (ADR-170), so self-serve sign-up cannot be used to
  spray organizations.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Commands.SeedTenantDefaults
  alias Palee.Organizations.Domain.{GoLivePolicy, OrganizationPolicy}
  alias Palee.Organizations.OrganizationStore

  @kinds GoLivePolicy.gated_kinds()

  def call(%{id: user_id}, kind, params, opts \\ []) when is_binary(user_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    seed_defaults = SeedTenantDefaults.seed_option(opts)

    with :ok <- validate_kind(kind),
         :ok <- ensure_allowed(user_id, kind) do
      OrganizationStore.transaction(fn ->
        with {:ok, organization} <-
               OrganizationStore.create_organization(organization_params(kind, params)),
             {:ok, _membership} <-
               RepoContext.run(%{organization_id: organization.id, user_id: user_id}, fn ->
                 OrganizationStore.add_membership(
                   owner_membership(kind, organization, user_id, now)
                 )
               end),
             {:ok, _defaults} <- SeedTenantDefaults.run(organization.id, user_id, seed_defaults) do
          {:ok, organization}
        end
      end)
    end
  end

  defp validate_kind(kind) when kind in @kinds, do: :ok
  defp validate_kind(_kind), do: {:error, :invalid_business_kind}

  defp owner_membership("coach", organization, user_id, now) do
    %{
      organization_id: organization.id,
      user_id: user_id,
      role: :owner,
      roles: [:owner, :coach],
      coach_scope: :all,
      status: :active,
      joined_at: now
    }
  end

  defp owner_membership(_gym, organization, user_id, now) do
    %{
      organization_id: organization.id,
      user_id: user_id,
      role: :owner,
      roles: [:owner],
      status: :active,
      joined_at: now
    }
  end

  defp organization_params(kind, params) do
    %{
      name: value(params, :name),
      provider_kind: kind,
      activation: "demo",
      slug: free_slug(value(params, :name), kind),
      timezone: value(params, :timezone),
      timezone_source: value(params, :timezone_source),
      default_locale: value(params, :default_locale)
    }
  end

  # The business's own slug, else a numbered one, else a random suffix (the
  # unique index still settles a race).
  defp free_slug(name, kind) do
    candidates = OrganizationPolicy.slug_candidates(name || "", kind)

    Enum.find(candidates, &(not OrganizationStore.slug_taken?(&1))) ||
      "#{hd(candidates)}-#{:crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)}"
  end

  defp ensure_allowed(user_id, kind) do
    owned =
      RepoContext.run(%{user_id: user_id}, fn ->
        user_id
        |> OrganizationStore.list_memberships()
        |> Enum.filter(fn %{membership: membership} -> :owner in membership.roles end)
        |> Enum.map(& &1.organization)
      end)

    cond do
      kind == "coach" and Enum.any?(owned, &(&1.provider_kind == "coach")) ->
        {:error, :coach_practice_exists}

      Enum.any?(owned, &GoLivePolicy.gated?/1) ->
        {:error, :business_account_exists}

      true ->
        :ok
    end
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
