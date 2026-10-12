defmodule MilosTraining.Organizations.OrganizationSlugAlias do
  @moduledoc """
  A path slug an organization has retired (ADR-112).

  Retired slugs keep resolving to their organization and stay reserved for it
  for as long as the organization exists, so bookmarked and shared
  `/org/<old>/...` links never start pointing at a different tenant.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.OrganizationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_slug_aliases" do
    field :organization_id, :binary_id
    field :slug, :string
    field :retired_at, :utc_datetime_usec
    field :retired_by_user_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(slug_alias \\ %__MODULE__{}, params) do
    slug_alias
    |> cast(params, [:organization_id, :slug, :retired_at, :retired_by_user_id])
    |> validate_required([:organization_id, :slug, :retired_at])
    |> validate_change(:slug, fn :slug, slug ->
      if OrganizationPolicy.valid_slug?(slug),
        do: [],
        else: [slug: "must be a 3-63 character URL-safe slug"]
    end)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:organization_id)
  end
end
