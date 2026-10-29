defmodule Palee.Imports.ImportRow do
  @moduledoc "One data row of an import, its plan and what applying it created (ADR-254)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(import_id row_number cells fingerprint status outcome warnings errors result
             user_id error_code applied_at)a

  schema "import_rows" do
    field :organization_id, :binary_id, read_after_writes: true
    field :import_id, :binary_id
    field :row_number, :integer
    field :cells, {:array, :string}, default: []
    field :fingerprint, :string
    field :status, :string, default: "pending"
    field :outcome, :string
    field :warnings, {:array, :map}, default: []
    field :errors, {:array, :map}, default: []
    field :result, :map, default: %{}
    field :user_id, :binary_id
    field :error_code, :string
    field :applied_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, @fields)
    |> validate_required([:import_id, :row_number, :status])
    |> unique_constraint(:fingerprint, name: :import_rows_applied_fingerprint_index)
    |> check_constraint(:status, name: :import_rows_check)
  end
end
