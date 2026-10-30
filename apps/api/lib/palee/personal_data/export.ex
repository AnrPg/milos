defmodule Palee.PersonalData.Export do
  @moduledoc """
  ADR-267: one request of a profile for a copy of its own data. Built in the
  background, stored privately under the profile's storage prefix (`file`:
  name, key, bytes, sha256), offered until `expires_at`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.PersonalData.Domain.ExportPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "personal_data_exports" do
    field :user_id, :binary_id
    field :status, :string, default: "pending"
    field :record_count, :integer
    field :file, :map
    field :error, :string
    field :requested_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :requested_at])
    |> validate_required([:user_id, :requested_at])
    |> unique_constraint(:user_id, name: :personal_data_exports_one_pending_index)
  end

  def finish_changeset(export, attrs) do
    export
    |> cast(attrs, [:status, :record_count, :file, :error, :completed_at, :expires_at])
    |> validate_inclusion(:status, ExportPolicy.statuses())
    |> validate_length(:error, max: 500)
  end
end
