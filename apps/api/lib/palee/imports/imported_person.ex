defmodule Palee.Imports.ImportedPerson do
  @moduledoc """
  A person an import brought into the business or matched (ADR-254), with
  the email and phone key later rows and files match on.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(user_id import_id created_profile name email phone_key external_id credit_entry_id
             invited_at invitation_id removed_at)a

  schema "imported_people" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :import_id, :binary_id
    field :created_profile, :boolean, default: false
    field :name, :string
    field :email, :string
    field :phone_key, :string
    field :external_id, :string
    field :credit_entry_id, :binary_id
    field :invited_at, :utc_datetime_usec
    field :invitation_id, :binary_id
    field :removed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(person, attrs) do
    person
    |> cast(attrs, @fields)
    |> validate_required([:user_id, :import_id])
    |> unique_constraint([:organization_id, :user_id])
  end
end
