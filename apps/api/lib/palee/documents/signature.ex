defmodule Palee.Documents.Signature do
  @moduledoc """
  A simple electronic signature with its evidence (ADR-252). Insert-only:
  the database refuses changes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  @fields ~w(id template_id version_id version_number request_id user_id signed_at level
             provider content_hash typed_name drawn_signature ip_address user_agent account
             evidence_hash evidence_object_key evidence_sha256 evidence_byte_size)a

  schema "document_signatures" do
    field :organization_id, :binary_id
    field :template_id, :binary_id
    field :version_id, :binary_id
    field :version_number, :integer
    field :request_id, :binary_id
    field :user_id, :binary_id
    field :signed_at, :utc_datetime_usec
    field :level, :string, default: "simple"
    field :provider, :string, default: "palee"
    field :content_hash, :string
    field :typed_name, :string
    field :drawn_signature, :map
    field :ip_address, :string
    field :user_agent, :string
    field :account, :map
    field :evidence_hash, :string
    field :evidence_object_key, :string
    field :evidence_sha256, :string
    field :evidence_byte_size, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def fields, do: @fields

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id | @fields])
    |> validate_required(
      ~w(id template_id version_id version_number user_id signed_at content_hash account
         evidence_hash evidence_object_key evidence_sha256 evidence_byte_size)a
    )
    |> check_constraint(:typed_name, name: :document_signatures_check)
  end
end
