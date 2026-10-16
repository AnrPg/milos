defmodule MilosTraining.Journal.Note do
  @moduledoc """
  Σημείωση (ADR-139, vision §7.7): a member's own note on technique, a
  thought, their mood or a goal, optionally about one workout. Private by
  default; written in a gym (provenance) or personally; soft-deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Journal.Domain.Visibility

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @topics ~w(technique thought mood goal)
  @linked_kinds ~w(execution training_log workout)

  schema "journal_notes" do
    field(:user_id, :binary_id)
    field(:organization_id, :binary_id)
    field(:topic, :string)
    field(:body, :string)
    field(:linked_kind, :string)
    field(:linked_id, :binary_id)
    field(:written_at, :utc_datetime_usec)
    field(:written_tz, :string, default: "UTC")
    field(:journal_visibility, :string, default: "private")
    field(:deleted_at, :utc_datetime_usec)
    field(:lock_version, :integer, default: 1)

    timestamps(type: :utc_datetime_usec)
  end

  @editable ~w(topic body linked_kind linked_id written_at written_tz)a

  def topics, do: @topics
  def linked_kinds, do: @linked_kinds

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :organization_id, :journal_visibility | @editable])
    |> validate_required([:user_id, :topic, :body, :written_at, :journal_visibility])
    |> validate_common()
    |> foreign_key_constraint(:organization_id)
  end

  def update_changeset(%__MODULE__{} = note, attrs) do
    note
    |> cast(attrs, @editable)
    |> validate_required([:topic, :body, :written_at])
    |> validate_common()
    |> optimistic_lock(:lock_version)
  end

  def visibility_changeset(%__MODULE__{} = note, rung) do
    note
    |> change(journal_visibility: rung)
    |> validate_inclusion(:journal_visibility, Visibility.rungs())
    |> check_constraint(:journal_visibility, name: :journal_notes_journal_visibility_check)
  end

  def delete_changeset(%__MODULE__{} = note, %DateTime{} = now),
    do: change(note, deleted_at: now)

  defp validate_common(changeset) do
    changeset
    |> update_change(:body, &String.trim/1)
    |> validate_inclusion(:topic, @topics)
    |> validate_length(:body, min: 1, max: 4000)
    |> validate_inclusion(:linked_kind, @linked_kinds)
    |> validate_link()
    |> validate_time_zone()
    |> check_constraint(:linked_kind, name: :journal_notes_link_check)
  end

  defp validate_link(changeset) do
    case {get_field(changeset, :linked_kind), get_field(changeset, :linked_id)} do
      {nil, nil} -> changeset
      {kind, id} when is_binary(kind) and is_binary(id) -> changeset
      _partial -> add_error(changeset, :linked_id, "must be given together with linked_kind")
    end
  end

  defp validate_time_zone(changeset) do
    validate_change(changeset, :written_tz, fn :written_tz, zone ->
      case DateTime.now(zone) do
        {:ok, _now} -> []
        {:error, _reason} -> [written_tz: "is not a known time zone"]
      end
    end)
  end
end
