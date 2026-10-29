defmodule Palee.Documents.Template do
  @moduledoc "A box's document (ADR-252). Its text lives in immutable versions."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(kind title requirement status current_version_id current_version_number
             required_version_number created_by_id archived_at)a

  schema "document_templates" do
    field :organization_id, :binary_id
    field :kind, :string
    field :title, :string
    field :requirement, :string, default: "optional"
    field :status, :string, default: "active"
    field :current_version_id, :binary_id
    field :current_version_number, :integer, default: 0
    field :required_version_number, :integer, default: 0
    field :created_by_id, :binary_id
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, @fields)
    |> validate_required([:kind, :title, :requirement, :status])
    |> check_constraint(:kind, name: :document_templates_check)
  end
end
