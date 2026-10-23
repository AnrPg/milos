defmodule Palee.Organizations.Commands.EnsureOrganiserOrganization do
  @moduledoc """
  ADR-185 §1: the one-person organisation behind «Ως εγώ». The first time a
  person hosts an event as themselves, an organisation of kind `organiser`
  is created transparently: the person is its owner, it gets the tenant
  defaults the caller passes (`opts[:seed_defaults]`: its club and the free
  organiser plan) and a free slug. Every later call returns the same one.

  One per person: creations for an account queue on an advisory lock inside
  the transaction, so two taps at once still make one organisation.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Commands.SeedTenantDefaults
  alias Palee.Organizations.Domain.OrganizationPolicy
  alias Palee.Organizations.OrganizationStore

  @kind "organiser"

  @doc "The person's active organiser organisation, or nil."
  def find(user_id) when is_binary(user_id) do
    RepoContext.run(%{user_id: user_id}, fn -> owned(user_id) end)
  end

  @doc "`{:ok, organization, created?}`: the existing one, or a new one."
  def call(%{id: user_id}, params, opts \\ []) when is_binary(user_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    seed_defaults = SeedTenantDefaults.seed_option(opts)

    OrganizationStore.transaction(fn ->
      :ok = OrganizationStore.lock_for_creation("organiser:" <> user_id)

      case find(user_id) do
        %{} = organization -> {:ok, {organization, false}}
        nil -> create(user_id, params, now, seed_defaults)
      end
    end)
    |> case do
      {:ok, {organization, created?}} -> {:ok, organization, created?}
      error -> error
    end
  end

  defp create(user_id, params, now, seed_defaults) do
    with {:ok, organization} <-
           OrganizationStore.create_organization(organization_params(params)),
         {:ok, _membership} <-
           RepoContext.run(%{organization_id: organization.id, user_id: user_id}, fn ->
             OrganizationStore.add_membership(%{
               organization_id: organization.id,
               user_id: user_id,
               role: :owner,
               roles: [:owner],
               coach_scope: :all,
               status: :active,
               joined_at: now
             })
           end),
         {:ok, _defaults} <- SeedTenantDefaults.run(organization.id, user_id, seed_defaults) do
      {:ok, {organization, true}}
    end
  end

  defp owned(user_id) do
    user_id
    |> OrganizationStore.list_memberships()
    |> Enum.find_value(fn %{membership: membership, organization: organization} ->
      if :owner in membership.roles and organization.provider_kind == @kind, do: organization
    end)
  end

  defp organization_params(params) do
    name = value(params, :name)

    %{
      name: name,
      provider_kind: @kind,
      slug: free_slug(name),
      timezone: value(params, :timezone),
      timezone_source: value(params, :timezone) && "inferred",
      default_locale: value(params, :default_locale)
    }
  end

  # A slug of its own (the person's name), else numbered, else random; the
  # unique index still settles a race between people.
  defp free_slug(name) do
    candidates = OrganizationPolicy.slug_candidates(name || "", "events")

    Enum.find(candidates, &(not OrganizationStore.slug_taken?(&1))) ||
      "#{hd(candidates)}-#{:crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)}"
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
