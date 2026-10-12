defmodule MilosTraining.Finance.FinanceEntitlementUsageEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_entitlement_usage_entries" do
    field :organization_id, :binary_id, read_after_writes: true
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
    |> validate_allowance_key()
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

  # ADR-097 adds event visits, guest passes and open-gym visits.
  @allowance_keys ~w(
    class_visits coaching_touchpoints event_visits guest_passes open_gym_visits
    pt_sessions assessments form_reviews
  )

  defp validate_allowance_key(changeset) do
    validate_change(changeset, :allowance_key, fn :allowance_key, key ->
      cond do
        key in @allowance_keys -> []
        class_type_key?(key) -> []
        true -> [allowance_key: "is invalid"]
      end
    end)
  end

  defp class_type_key?("class_visits:" <> id), do: match?({:ok, _}, Ecto.UUID.cast(id))
  defp class_type_key?(_), do: false
end
