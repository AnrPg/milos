defmodule Palee.BusinessAccounts.DemoRecord do
  @moduledoc """
  ADR-184: one row a demo seeder wrote (`source` is its table), tracked so
  activation or «remove demo data» deletes exactly what was seeded and
  nothing the owner created.
  """

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "demo_records" do
    field :organization_id, :binary_id
    field :section, :string
    field :source, :string
    field :record_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @type t :: %__MODULE__{}
end
