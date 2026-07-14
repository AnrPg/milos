defmodule MilosTraining.Finance.FinanceSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_settings" do
    field :payment_reminder_interval_days, :integer, default: 7

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [:payment_reminder_interval_days])
    |> validate_required([:payment_reminder_interval_days])
    |> validate_number(:payment_reminder_interval_days, greater_than: 0)
  end
end
