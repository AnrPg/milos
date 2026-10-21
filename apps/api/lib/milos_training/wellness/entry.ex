defmodule MilosTraining.Wellness.Entry do
  @moduledoc """
  One wellness entry (ADR-159 §1): water, sleep or a meal, with its kind's
  value, the instant, the member's zone and the local day it counts for.
  Private by default; optional gym provenance; soft-deleted by its owner.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Journal.Domain.Visibility
  alias MilosTraining.Wellness.Domain.EntryKinds

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "wellness_entries" do
    field(:user_id, :binary_id)
    field(:organization_id, :binary_id)
    field(:kind, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:occurred_tz, :string, default: "UTC")
    field(:occurred_on, :date)
    field(:value, :map, default: %{})
    field(:source, :string, default: "manual")
    field(:external_id, :string)
    field(:corrected_at, :utc_datetime_usec)
    field(:journal_visibility, :string, default: "private")
    field(:deleted_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @create ~w(user_id organization_id kind occurred_at occurred_tz occurred_on value source
             external_id journal_visibility)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @create)
    |> validate_required([:user_id, :kind, :occurred_at, :occurred_tz, :occurred_on, :value])
    |> validate_inclusion(:kind, EntryKinds.kinds())
    |> validate_inclusion(:source, EntryKinds.sources())
    |> validate_inclusion(:journal_visibility, Visibility.rungs())
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:user_id, :source, :external_id], name: :wellness_entries_device_unique)
    |> check_constraint(:kind, name: :wellness_entries_kind_check)
  end

  @doc "A member's change: new value or time. A device row becomes «διορθώθηκε»."
  def change_changeset(%__MODULE__{} = entry, attrs, %DateTime{} = now) do
    entry
    |> cast(attrs, [:occurred_at, :occurred_tz, :occurred_on, :value])
    |> validate_required([:occurred_at, :occurred_tz, :occurred_on, :value])
    |> then(fn changeset ->
      if entry.source != "manual" and changeset.changes != %{},
        do: put_change(changeset, :corrected_at, now),
        else: changeset
    end)
  end

  @doc "A device's newer reading of the same row (ignored once corrected)."
  def device_changeset(%__MODULE__{} = entry, attrs) do
    cast(entry, attrs, [:occurred_at, :occurred_tz, :occurred_on, :value])
  end

  def visibility_changeset(%__MODULE__{} = entry, rung) do
    entry
    |> change(journal_visibility: rung)
    |> validate_inclusion(:journal_visibility, Visibility.rungs())
    |> check_constraint(:journal_visibility, name: :wellness_entries_journal_visibility_check)
  end

  def delete_changeset(%__MODULE__{} = entry, %DateTime{} = now),
    do: change(entry, deleted_at: now)
end
