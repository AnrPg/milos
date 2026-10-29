defmodule Palee.Fiscal.ExportSetting do
  @moduledoc "A gym's options for one accounting export format (ADR-245)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fiscal_export_settings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :format, :string
    field :options, :map, default: %{}
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(setting \\ %__MODULE__{}, attrs) do
    setting
    |> cast(attrs, [:format, :options, :updated_by_id])
    |> validate_required([:format, :options])
    |> unique_constraint([:organization_id, :format])
  end
end
