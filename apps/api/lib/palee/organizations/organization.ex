defmodule Palee.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Organizations.Domain.OrganizationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :slug, :string
    field :name, :string
    field :status, Ecto.Enum, values: OrganizationPolicy.statuses(), default: :active
    # ADR-162: `gym` or `coach` (an independent coach); set by the owner
    # (`Organizations.put_provider_kind/2`), never through `changeset/2`.
    field :provider_kind, :string, default: "gym"
    # ADR-184: `demo` until the platform team activates the business; set at
    # creation (`put_initial_activation/2`) and changed only by
    # `palee_activate_business/2`, never through `changeset/2`.
    field :activation, :string, default: "active"
    field :demo_started_at, :utc_datetime_usec
    field :activated_at, :utc_datetime_usec
    field :activated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

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

  @doc """
  ADR-170: the kind an organization is created with (an independent coach's
  practice starts as `coach`). Later changes go through
  `Organizations.put_provider_kind/2`.
  """
  def put_initial_provider_kind(changeset, nil), do: changeset

  def put_initial_provider_kind(changeset, kind) do
    changeset
    |> put_change(:provider_kind, kind)
    |> validate_inclusion(:provider_kind, ["gym", "coach", "organiser"])
  end

  @doc """
  ADR-184: a self-serve business (a gym or an independent coach) starts in
  demo mode; vendor-provisioned and pre-existing organizations are active.
  """
  def put_initial_activation(changeset, "demo") do
    changeset
    |> put_change(:activation, "demo")
    |> put_change(:demo_started_at, DateTime.utc_now())
  end

  def put_initial_activation(changeset, _activation), do: changeset

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
