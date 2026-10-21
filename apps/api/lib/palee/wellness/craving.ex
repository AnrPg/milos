defmodule Palee.Wellness.Craving do
  @moduledoc """
  Λιγούρα (ADR-159 §3, mockup 22). Private by default; the outcome can be set
  later; a support request is stamped when the member asks for it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Journal.Domain.Visibility
  alias Palee.Wellness.Domain.CravingPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "craving_entries" do
    field(:user_id, :binary_id)
    field(:organization_id, :binary_id)
    field(:occurred_at, :utc_datetime_usec)
    field(:occurred_tz, :string, default: "UTC")
    field(:occurred_on, :date)
    field(:intensity, :integer)
    field(:triggers, {:array, :string}, default: [])
    field(:outcome, :string)
    field(:outcome_at, :utc_datetime_usec)
    field(:note, :string)
    field(:support_requested_at, :utc_datetime_usec)
    field(:follow_up_at, :utc_datetime_usec)
    field(:followed_up_at, :utc_datetime_usec)
    field(:journal_visibility, :string, default: "private")
    field(:deleted_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @editable ~w(occurred_at occurred_tz occurred_on intensity triggers outcome outcome_at note
               support_requested_at follow_up_at)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :organization_id, :journal_visibility | @editable])
    |> validate_required([:user_id, :occurred_at, :occurred_tz, :occurred_on, :intensity])
    |> validate_common()
    |> foreign_key_constraint(:organization_id)
  end

  def change_changeset(%__MODULE__{} = craving, attrs) do
    craving
    |> cast(attrs, @editable)
    |> validate_required([:occurred_at, :occurred_tz, :occurred_on, :intensity])
    |> validate_common()
  end

  def followed_up_changeset(%__MODULE__{} = craving, %DateTime{} = at),
    do: change(craving, followed_up_at: at)

  def visibility_changeset(%__MODULE__{} = craving, rung) do
    craving
    |> change(journal_visibility: rung)
    |> validate_inclusion(:journal_visibility, Visibility.rungs())
    |> check_constraint(:journal_visibility, name: :craving_entries_journal_visibility_check)
  end

  def delete_changeset(%__MODULE__{} = craving, %DateTime{} = now),
    do: change(craving, deleted_at: now)

  defp validate_common(changeset) do
    range = CravingPolicy.intensity_range()

    changeset
    |> validate_number(:intensity,
      greater_than_or_equal_to: range.first,
      less_than_or_equal_to: range.last
    )
    |> validate_subset(:triggers, CravingPolicy.triggers())
    |> validate_inclusion(:outcome, CravingPolicy.outcomes())
    |> validate_length(:note, min: 1, max: CravingPolicy.note_max())
    |> validate_inclusion(:journal_visibility, Visibility.rungs())
    |> check_constraint(:outcome, name: :craving_entries_outcome_check)
  end
end
