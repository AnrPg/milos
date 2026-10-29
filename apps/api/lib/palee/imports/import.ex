defmodule Palee.Imports.Import do
  @moduledoc "One uploaded file and the state of importing it (ADR-254)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(created_by_id status source filename byte_size sha256 encoding delimiter header
             row_count mapping date_order default_role file_warnings preview previewed_at summary
             applied_by_id queued_at started_at finished_at undone_at undone_by_id last_error)a

  schema "imports" do
    field :organization_id, :binary_id, read_after_writes: true
    field :created_by_id, :binary_id
    field :status, :string, default: "draft"
    field :source, :string
    field :filename, :string
    field :byte_size, :integer
    field :sha256, :string
    field :encoding, :string
    field :delimiter, :string
    field :header, {:array, :string}, default: []
    field :row_count, :integer
    field :mapping, {:array, :map}, default: []
    field :date_order, :string
    field :default_role, :string, default: "member"
    field :file_warnings, {:array, :string}, default: []
    field :preview, :map
    field :previewed_at, :utc_datetime_usec
    field :summary, :map
    field :applied_by_id, :binary_id
    field :queued_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :undone_at, :utc_datetime_usec
    field :undone_by_id, :binary_id
    field :last_error, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(import, attrs) do
    import
    |> cast(attrs, @fields)
    |> validate_required([:status, :source, :filename, :byte_size, :sha256, :encoding])
    |> validate_required([:delimiter, :row_count, :date_order, :default_role])
    |> check_constraint(:status, name: :imports_check)
  end
end
