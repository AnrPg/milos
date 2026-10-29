defmodule Palee.Documents.Version do
  @moduledoc "One published version of a document. Insert-only: the database refuses changes."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  @fields ~w(id template_id number title body language change_kind content_hash
             published_by_id published_at)a

  schema "document_versions" do
    field :organization_id, :binary_id
    field :template_id, :binary_id
    field :number, :integer
    field :title, :string
    field :body, :string
    field :language, :string
    field :change_kind, :string
    field :content_hash, :string
    field :published_by_id, :binary_id
    field :published_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id | @fields])
    |> validate_required(
      ~w(id template_id number title body language change_kind content_hash published_at)a
    )
    |> unique_constraint([:template_id, :number])
    |> check_constraint(:number, name: :document_versions_check)
  end
end
