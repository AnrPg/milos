defmodule Palee.Finance.FinanceSubscriptionFreeze do
  @moduledoc "A dated pause of a package subscription (ADR-097)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_subscription_freezes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :starts_on, :date
    field :ends_on, :date
    field :extension_days, :integer, default: 0
    field :reason, :string
    field :admin_id, :binary_id
    field :cancelled_at, :utc_datetime_usec
    field :cancel_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(freeze \\ %__MODULE__{}, params) do
    freeze
    |> cast(params, [
      :membership_id,
      :membership_package_subscription_id,
      :starts_on,
      :ends_on,
      :extension_days,
      :reason,
      :admin_id
    ])
    |> validate_required([
      :membership_id,
      :membership_package_subscription_id,
      :starts_on,
      :ends_on,
      :reason
    ])
    |> validate_length(:reason, min: 3, max: 500)
    |> validate_number(:extension_days, greater_than_or_equal_to: 0)
    |> check_constraint(:ends_on, name: :finance_subscription_freezes_dates)
    |> foreign_key_constraint(:membership_package_subscription_id)
  end

  def cancel_changeset(freeze, params) do
    freeze
    |> cast(params, [:cancelled_at, :cancel_reason, :ends_on, :extension_days])
    |> validate_required([:cancelled_at, :cancel_reason])
    |> validate_length(:cancel_reason, min: 3, max: 500)
  end
end
