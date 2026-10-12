defmodule MilosTraining.Finance.FinanceCorporateClient do
  @moduledoc "A company paying for its employees' seats on a corporate package (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_corporate_clients" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_package_id, :binary_id
    field :company_name, :string
    field :billing_email, :string
    field :contact_name, :string
    field :enrollment_code, :string
    field :status, :string, default: "active"

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :membership_package_id,
      :company_name,
      :billing_email,
      :contact_name,
      :enrollment_code
    ])
    |> validate_required([:membership_package_id, :company_name, :enrollment_code])
    |> validate_fields()
    |> unique_constraint([:organization_id, :membership_package_id],
      name: :finance_corporate_clients_package_index,
      message: "already has a corporate client"
    )
    |> unique_constraint([:organization_id, :enrollment_code],
      name: :finance_corporate_clients_code_index
    )
  end

  def update_changeset(client, params) do
    client
    |> cast(params, [:company_name, :billing_email, :contact_name, :status, :enrollment_code])
    |> validate_fields()
    |> validate_inclusion(:status, ["active", "archived"])
  end

  defp validate_fields(changeset) do
    changeset
    |> validate_length(:company_name, min: 2, max: 120)
    |> validate_length(:contact_name, max: 120)
    |> validate_format(:billing_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end
end
