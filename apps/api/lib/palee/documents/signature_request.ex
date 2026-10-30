defmodule Palee.Documents.SignatureRequest do
  @moduledoc "A request that one person signs a document (ADR-252)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(template_id user_id batch_id audience status requested_by_id requested_at
             signature_id closed_at)a

  schema "document_signature_requests" do
    field :organization_id, :binary_id
    field :template_id, :binary_id
    field :user_id, :binary_id
    field :batch_id, :binary_id
    field :audience, :string, default: "person"
    field :status, :string, default: "pending"
    field :requested_by_id, :binary_id
    field :requested_at, :utc_datetime_usec
    field :signature_id, :binary_id
    field :closed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def fields, do: @fields

  def changeset(request, attrs) do
    request
    |> cast(attrs, @fields)
    |> validate_required([:template_id, :user_id, :status, :requested_at])
    |> unique_constraint([:template_id, :user_id],
      name: :document_signature_requests_pending_index
    )
  end
end
