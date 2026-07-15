defmodule MilosTraining.Finance.FinanceEntitlementUsageEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_entitlement_usage_entries" do
    field :membership_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :allowance_key, :string
    field :event_type, :string
    field :quantity_delta, :integer
    field :period_start, :date
    field :period_end, :date
    field :source_context, :string
    field :source_id, :binary_id
    field :parent_entry_id, :binary_id
    field :admin_id, :binary_id
    field :reason, :string
    field :idempotency_key, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry \\ %__MODULE__{}, params) do
    entry
    |> cast(params, [
      :membership_id,
      :membership_package_subscription_id,
      :allowance_key,
      :event_type,
      :quantity_delta,
      :period_start,
      :period_end,
      :source_context,
      :source_id,
      :parent_entry_id,
      :admin_id,
      :reason,
      :idempotency_key,
      :metadata
    ])
    |> validate_required([
      :membership_id,
      :membership_package_subscription_id,
      :allowance_key,
      :event_type,
      :quantity_delta,
      :period_start,
      :period_end,
      :source_context,
      :idempotency_key
    ])
    |> validate_inclusion(:allowance_key, ["class_visits", "coaching_touchpoints"])
    |> validate_inclusion(:event_type, ["reserve", "finalize", "release", "consume", "adjustment"])
    |> validate_reason_for_adjustment()
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:membership_package_subscription_id)
    |> foreign_key_constraint(:parent_entry_id)
    |> foreign_key_constraint(:admin_id)
    |> unique_constraint(:idempotency_key)
  end

  defp validate_reason_for_adjustment(changeset) do
    if get_field(changeset, :event_type) == "adjustment" do
      validate_required(changeset, [:admin_id, :reason])
    else
      changeset
    end
  end
end
