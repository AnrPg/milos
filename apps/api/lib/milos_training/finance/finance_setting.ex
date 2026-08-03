defmodule MilosTraining.Finance.FinanceSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_settings" do
    field :organization_id, :binary_id
    field :payment_reminder_interval_days, :integer, default: 7
    field :entitlement_enforcement_mode, :string, default: "observe"
    field :entitlement_timezone, :string, default: "Europe/Athens"
    field :document_mode, :string, default: "invoice"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [
      :payment_reminder_interval_days,
      :entitlement_enforcement_mode,
      :entitlement_timezone,
      :document_mode
    ])
    |> validate_required([
      :payment_reminder_interval_days,
      :entitlement_enforcement_mode,
      :entitlement_timezone,
      :document_mode
    ])
    |> validate_number(:payment_reminder_interval_days, greater_than: 0)
    |> validate_inclusion(:entitlement_enforcement_mode, [
      "observe",
      "enforce_managed",
      "enforce_all"
    ])
    |> validate_length(:entitlement_timezone, min: 1, max: 100)
    |> validate_inclusion(:document_mode, ["invoice", "receipt"])
  end
end
