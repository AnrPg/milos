defmodule Palee.Finance.FinanceValueOverride do
  @moduledoc "ADR-274: a value Palee works out that staff set by hand, and its history."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Finance.Domain.ValueOverride

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_value_overrides" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_id, :binary_id
    field :subject_type, :string
    field :subject_id, :binary_id
    field :field, :string
    field :computed_value, :string
    field :value, :string
    field :reason, :string
    field :set_by_id, :binary_id
    field :ended_at, :utc_datetime_usec
    field :ended_by_id, :binary_id
    field :end_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(override \\ %__MODULE__{}, params) do
    override
    |> cast(params, [
      :membership_id,
      :subject_type,
      :subject_id,
      :field,
      :computed_value,
      :value,
      :reason,
      :set_by_id
    ])
    |> validate_required([:membership_id, :subject_type, :subject_id, :field, :value])
    |> validate_inclusion(:field, ValueOverride.fields())
    |> validate_inclusion(:subject_type, ["membership", "subscription"])
    |> validate_length(:reason, max: 500)
    |> unique_constraint([:subject_id, :field], name: :finance_value_overrides_in_force_index)
  end

  def end_changeset(override, params) do
    override
    |> cast(params, [:ended_at, :ended_by_id, :end_reason])
    |> validate_required([:ended_at, :end_reason])
    |> validate_inclusion(:end_reason, ValueOverride.end_reasons())
  end
end
