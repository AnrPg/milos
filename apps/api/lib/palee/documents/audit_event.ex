defmodule Palee.Documents.AuditEvent do
  @moduledoc "One audited documents action (ADR-252). Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(action actor_id subject_type subject_id subject_user_id details occurred_at)a

  schema "document_audit_events" do
    field :organization_id, :binary_id
    field :action, :string
    field :actor_id, :binary_id
    field :subject_type, :string
    field :subject_id, :binary_id
    field :subject_user_id, :binary_id
    field :details, :map, default: %{}
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def fields, do: @fields

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id | @fields])
    |> validate_required([:action, :subject_type, :occurred_at])
  end
end
