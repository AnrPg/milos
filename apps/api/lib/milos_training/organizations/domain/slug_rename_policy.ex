defmodule MilosTraining.Organizations.Domain.SlugRenamePolicy do
  @moduledoc """
  Pure rules for renaming an organization's path slug (ADR-104).

  A slug rename moves `canonical_path`, every `/org/:slug` route and every
  bookmarked or shared tenant link, so it is guarded three ways:

    * the vendor must retype the *current* slug (typed confirmation);
    * the requested slug must satisfy `OrganizationPolicy.valid_slug?/1`
      exactly as typed - it is never silently re-slugified;
    * the slug must be free: not another organization's canonical slug and
      not another organization's retired alias. Retired aliases are reserved
      for their organization indefinitely (until it is deleted), which is
      what lets an organization rename back to one of its own old slugs.
  """

  alias MilosTraining.Organizations.Domain.OrganizationPolicy

  @typedoc """
  Who currently holds a slug: nobody, an organization as its canonical slug,
  or an organization as a retired alias.
  """
  @type claim :: nil | {:organization, binary()} | {:alias, binary()}

  @type plan :: %{slug: String.t(), retire: String.t(), reclaim_alias: boolean()}

  @doc "Normalizes the requested slug for comparison (trim + lowercase) and validates it."
  @spec requested_slug(term()) :: {:ok, String.t()} | {:error, :invalid_slug}
  def requested_slug(value) when is_binary(value) do
    slug = value |> String.trim() |> String.downcase()
    if OrganizationPolicy.valid_slug?(slug), do: {:ok, slug}, else: {:error, :invalid_slug}
  end

  def requested_slug(_value), do: {:error, :invalid_slug}

  @doc "The vendor must retype the organization's current slug exactly (surrounding whitespace ignored)."
  @spec verify_confirmation(String.t(), term()) :: :ok | {:error, :slug_confirmation_mismatch}
  def verify_confirmation(current_slug, typed)
      when is_binary(current_slug) and is_binary(typed) do
    if String.trim(typed) == current_slug,
      do: :ok,
      else: {:error, :slug_confirmation_mismatch}
  end

  def verify_confirmation(_current_slug, _typed), do: {:error, :slug_confirmation_mismatch}

  @doc """
  Decides whether `organization_id` may move from `current_slug` to
  `requested_slug` given who currently holds the requested slug.
  """
  @spec plan(binary(), String.t(), String.t(), claim()) ::
          {:ok, plan()} | {:error, :slug_unchanged | :slug_taken}
  def plan(_organization_id, slug, slug, _claim), do: {:error, :slug_unchanged}

  def plan(_organization_id, current_slug, requested_slug, nil),
    do: {:ok, %{slug: requested_slug, retire: current_slug, reclaim_alias: false}}

  def plan(organization_id, current_slug, requested_slug, {:alias, organization_id}),
    do: {:ok, %{slug: requested_slug, retire: current_slug, reclaim_alias: true}}

  def plan(_organization_id, _current_slug, _requested_slug, {:alias, _other}),
    do: {:error, :slug_taken}

  def plan(_organization_id, _current_slug, _requested_slug, {:organization, _other}),
    do: {:error, :slug_taken}
end
