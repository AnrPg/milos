defmodule MilosTraining.Journal.JournalExport do
  @moduledoc """
  A member's export of their whole journal across providers (ADR-162):
  built in the background, stored privately under the member's prefix, kept
  until `expires_at`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses ~w(pending ready failed)

  schema "journal_exports" do
    field(:user_id, :binary_id)
    field(:status, :string, default: "pending")
    field(:entry_count, :integer)
    field(:files, {:array, :map}, default: [])
    field(:error, :string)
    field(:requested_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :requested_at])
    |> validate_required([:user_id, :requested_at])
  end

  def finish_changeset(export, attrs) do
    export
    |> cast(attrs, [:status, :entry_count, :files, :error, :completed_at, :expires_at])
    |> validate_inclusion(:status, @statuses)
  end
end
