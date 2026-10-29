defmodule Palee.Finance.MembershipPackage do
  use Ecto.Schema
  import Ecto.Changeset
  alias Palee.Finance.Domain.{EntitlementPlan, PackageCode, PackageType}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "membership_packages" do
    field :organization_id, :binary_id, read_after_writes: true
    field :code, :string
    field :name, :string
    field :description, :string
    field :family, :string
    field :package_type, :string, default: "membership"
    field :billing_period, :string
    field :base_price_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :tags, {:array, :string}, default: []
    field :params, :map, default: %{}
    field :active, :boolean, default: true
    # ADR-248: members can buy it themselves, online.
    field :sold_online, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(package \\ %__MODULE__{}, params) do
    package
    |> cast(params, [
      :code,
      :name,
      :description,
      :package_type,
      :billing_period,
      :base_price_cents,
      :currency,
      :tags,
      :params,
      :active,
      :sold_online
    ])
    |> update_change(:code, &PackageCode.normalize/1)
    |> validate_required([:name, :package_type, :billing_period])
    |> validate_inclusion(:package_type, PackageType.keys())
    |> validate_inclusion(:billing_period, PackageType.all_billing_periods())
    |> put_family_from_type()
    |> validate_number(:base_price_cents, greater_than_or_equal_to: 0)
    |> validate_entitlement_plan()
    |> unique_constraint([:organization_id, :code],
      name: :membership_packages_organization_code_index
    )
  end

  # ADR-096: family is the reporting label of the package type and is never authored.
  defp put_family_from_type(changeset) do
    case get_field(changeset, :package_type) do
      nil -> changeset
      type -> put_change(changeset, :family, type)
    end
  end

  defp validate_entitlement_plan(changeset) do
    params = get_field(changeset, :params) || %{}

    if Map.has_key?(params, "entitlement_version") or Map.has_key?(params, :entitlement_version) do
      case EntitlementPlan.parse(params) do
        {:ok, _plan} ->
          changeset

        {:error, reason} ->
          add_error(changeset, :params, "invalid entitlement plan: #{inspect(reason)}")
      end
    else
      changeset
    end
  end
end
