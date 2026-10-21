defmodule Palee.Finance.FinanceSubscriptionBeneficiary do
  @moduledoc "A person who shares a payer's subscription (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_subscription_beneficiaries" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_package_subscription_id, :binary_id
    field :membership_id, :binary_id
    field :is_minor, :boolean, default: false
    field :added_by_id, :binary_id
    field :removed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:membership_package_subscription_id, :membership_id, :is_minor, :added_by_id])
    |> validate_required([:membership_package_subscription_id, :membership_id])
    |> unique_constraint([:membership_package_subscription_id, :membership_id],
      name: :finance_subscription_beneficiaries_active_index,
      message: "is already a beneficiary"
    )
  end

  def remove_changeset(beneficiary, removed_at), do: change(beneficiary, removed_at: removed_at)
end
