defmodule Palee.Documents.HealthCertificate do
  @moduledoc """
  A member's health certificate (Βεβαίωση υγείας, ADR-252): only the dates
  and the uploaded file, never what the doctor wrote (GDPR art. 9).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(user_id issued_on expires_on file_key content_type byte_size uploaded_by_id
             reminded_for)a

  schema "health_certificates" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :issued_on, :date
    field :expires_on, :date
    field :file_key, :string
    field :content_type, :string
    field :byte_size, :integer
    field :uploaded_by_id, :binary_id
    field :reminded_for, :date

    timestamps(type: :utc_datetime_usec)
  end

  def fields, do: @fields

  def changeset(certificate, attrs) do
    certificate
    |> cast(attrs, @fields)
    |> validate_required([
      :user_id,
      :issued_on,
      :expires_on,
      :file_key,
      :content_type,
      :byte_size
    ])
    |> unique_constraint(:file_key)
    |> check_constraint(:expires_on, name: :health_certificates_check)
  end
end
