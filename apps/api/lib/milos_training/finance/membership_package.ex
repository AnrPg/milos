defmodule MilosTraining.Finance.MembershipPackage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "membership_packages" do
    field :code, :string
    field :name, :string
    field :description, :string
    field :family, :string
    field :billing_period, :string
    field :base_price_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :tags, {:array, :string}, default: []
    field :params, :map, default: %{}
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(package \\ %__MODULE__{}, params) do
    package
    |> cast(params, [
      :code,
      :name,
      :description,
      :family,
      :billing_period,
      :base_price_cents,
      :currency,
      :tags,
      :params,
      :active
    ])
    |> update_change(:code, &normalize_code/1)
    |> validate_required([:code, :name, :family, :billing_period])
    |> validate_inclusion(:billing_period, ["monthly", "quarterly", "annual", "custom"])
    |> validate_number(:base_price_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:code)
  end

  defp normalize_code(nil), do: nil

  defp normalize_code(code) do
    code
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> String.trim("_")
  end
end
