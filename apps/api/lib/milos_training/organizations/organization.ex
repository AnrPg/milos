defmodule MilosTraining.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.OrganizationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :slug, :string
    field :name, :string
    field :status, Ecto.Enum, values: OrganizationPolicy.statuses(), default: :active

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(organization \\ %__MODULE__{}, params) do
    organization
    |> cast(params, [:slug, :name, :status])
    |> update_change(:name, &String.trim/1)
    |> derive_slug()
    |> validate_required([:slug, :name, :status])
    |> validate_length(:name, min: 2, max: 120)
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  defp derive_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        put_change(
          changeset,
          :slug,
          OrganizationPolicy.normalize_slug(get_field(changeset, :name))
        )

      _explicit_slug ->
        changeset
    end
  end

  defp validate_slug(changeset) do
    validate_change(changeset, :slug, fn :slug, slug ->
      if OrganizationPolicy.valid_slug?(slug),
        do: [],
        else: [slug: "must be a 3-63 character URL-safe slug"]
    end)
  end
end
