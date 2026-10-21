defmodule Palee.Coaching.Note do
  @moduledoc "A coach's private note about a client (ADR-101)."

  use Ecto.Schema
  import Ecto.Changeset

  # ADR-140 §5: what the note is about, when it is about one thing.
  @subject_kinds ~w(execution training_log pr injury form_review assignment)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "coaching_notes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :coach_user_id, :binary_id
    field :client_user_id, :binary_id
    field :body, :string
    field :subject_kind, :string
    field :subject_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(note \\ %__MODULE__{}, attrs) do
    note
    |> cast(attrs, [
      :organization_id,
      :coach_user_id,
      :client_user_id,
      :body,
      :subject_kind,
      :subject_id
    ])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:coach_user_id, :client_user_id, :body])
    |> validate_length(:body, min: 1, max: 5_000)
    |> validate_inclusion(:subject_kind, @subject_kinds)
    |> validate_subject_pair()
    |> check_constraint(:subject_kind, name: :coaching_notes_subject_check)
    |> check_constraint(:subject_id, name: :coaching_notes_subject_owner_check)
  end

  def subject_kinds, do: @subject_kinds

  defp validate_subject_pair(changeset) do
    case {get_field(changeset, :subject_kind), get_field(changeset, :subject_id)} do
      {nil, nil} -> changeset
      {kind, id} when is_binary(kind) and is_binary(id) -> changeset
      {nil, _id} -> add_error(changeset, :subject_kind, "is required with a subject")
      {_kind, nil} -> add_error(changeset, :subject_id, "is required with a subject kind")
    end
  end
end
