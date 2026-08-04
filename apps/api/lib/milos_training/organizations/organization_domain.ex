defmodule MilosTraining.Organizations.OrganizationDomain do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @hostname_pattern ~r/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/

  schema "organization_domains" do
    field :organization_id, :binary_id
    field :host, :string
    field :verified_at, :utc_datetime_usec
    field :primary, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(domain \\ %__MODULE__{}, params) do
    domain
    |> cast(params, [:organization_id, :host, :verified_at, :primary])
    |> update_change(:host, &normalize_host/1)
    |> validate_required([:organization_id, :host, :primary])
    |> validate_format(:host, @hostname_pattern, message: "must be a bare hostname")
    |> unique_constraint(:host)
    |> unique_constraint(:organization_id,
      name: :organization_domains_one_primary_per_organization
    )
    |> foreign_key_constraint(:organization_id)
  end

  defp normalize_host(host) do
    host
    |> String.trim()
    |> String.downcase()
    |> String.trim_trailing(".")
  end
end
