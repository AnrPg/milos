defmodule Palee.Finance.FinanceAccountingExport do
  @moduledoc """
  Audit record of one accounting export run (ADR-126): requester, range,
  execution mode, status and the stored artifact's key, size and SHA-256.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["queued", "running", "completed", "failed"]

  schema "finance_accounting_exports" do
    field :organization_id, :binary_id, read_after_writes: true
    field :requested_by_id, :binary_id
    field :range_start, :date
    field :range_end, :date
    field :status, :string, default: "queued"
    field :execution_mode, :string
    field :schema_version, :integer, default: 1
    field :object_key, :string
    field :byte_size, :integer
    field :sha256, :string
    field :row_counts, :map, default: %{}
    field :files, {:array, :map}, default: []
    field :error_reason, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :requested_by_id,
      :range_start,
      :range_end,
      :status,
      :execution_mode,
      :schema_version
    ])
    |> validate_required([:range_start, :range_end, :execution_mode, :schema_version])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:execution_mode, ["inline", "background"])
    |> check_constraint(:range_end, name: :finance_accounting_exports_range_check)
    |> foreign_key_constraint(:requested_by_id)
  end

  def progress_changeset(%__MODULE__{} = export, params) do
    export
    |> cast(params, [
      :status,
      :object_key,
      :byte_size,
      :sha256,
      :row_counts,
      :files,
      :error_reason,
      :started_at,
      :completed_at
    ])
    |> validate_inclusion(:status, @statuses)
  end
end
