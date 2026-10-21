defmodule Palee.Journal.Comment do
  @moduledoc """
  Σχόλιο (ADR-140 §1): text a member writes on one of their own entries
  (an execution, a training-log entry or a PR), wherever it is written. It
  is anchored to the whole entry, a section, an exercise or a selection of
  its text; it has text and/or tags and may carry a structured change in
  the modification-patch shape (`change`, upserted by `change_key`). It has
  no rung of its own and is read through its entry's rung.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entry_kinds ~w(execution training_log pr)
  @body_max 4000

  schema "journal_comments" do
    field(:user_id, :binary_id)
    field(:organization_id, :binary_id)
    field(:entry_kind, :string)
    field(:entry_id, :binary_id)
    field(:section_id, :string)
    field(:exercise_id, :string)
    field(:selected_text, :string)
    field(:selection_start, :integer)
    field(:selection_end, :integer)
    field(:tags, {:array, :string}, default: [])
    field(:body, :string)
    field(:change, :map)
    field(:change_key, :string)
    field(:written_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @content ~w(section_id exercise_id selected_text selection_start selection_end tags body change)a

  def entry_kinds, do: @entry_kinds

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :user_id,
      :organization_id,
      :entry_kind,
      :entry_id,
      :written_at | @content
    ])
    |> validate_required([:user_id, :entry_kind, :entry_id, :written_at])
    |> validate_inclusion(:entry_kind, @entry_kinds)
    |> validate_content()
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(:change_key, name: :journal_comments_change_key_index)
  end

  def update_changeset(%__MODULE__{} = comment, attrs) do
    comment
    |> cast(attrs, @content)
    |> validate_content()
    |> unique_constraint(:change_key, name: :journal_comments_change_key_index)
  end

  def delete_changeset(%__MODULE__{} = comment, %DateTime{} = now),
    do: change(comment, deleted_at: now)

  defp validate_content(changeset) do
    changeset
    |> update_change(:body, &blank_to_nil/1)
    |> update_change(:selected_text, &blank_to_nil/1)
    |> update_change(:section_id, &blank_to_nil/1)
    |> update_change(:exercise_id, &blank_to_nil/1)
    |> update_change(:tags, &normalize_tags/1)
    |> validate_length(:body, max: @body_max)
    |> validate_length(:section_id, max: 200)
    |> validate_length(:exercise_id, max: 200)
    |> validate_length(:selected_text, max: 1000)
    |> validate_selection()
    |> validate_change_patch()
    |> validate_has_content()
    |> check_constraint(:body, name: :journal_comments_content_check)
  end

  defp validate_selection(changeset) do
    case {get_field(changeset, :selection_start), get_field(changeset, :selection_end)} do
      {nil, nil} ->
        changeset

      {start, stop} when is_integer(start) and is_integer(stop) and start >= 0 and stop > start ->
        changeset

      _invalid ->
        add_error(changeset, :selection_start, "is not a valid range")
    end
  end

  # A change is a modification patch, already normalized by the Execution
  # context (ModificationPatchValidator); its `patch_id` becomes the stable
  # `change_key` the comment is upserted by.
  defp validate_change_patch(changeset) do
    case fetch_change(changeset, :change) do
      :error ->
        changeset

      {:ok, nil} ->
        put_change(changeset, :change_key, nil)

      {:ok, %{"patch_id" => key} = patch} when is_binary(key) and key != "" ->
        changeset
        |> put_change(:change, Map.drop(patch, ["note", "logged_at"]))
        |> put_change(:change_key, key)
        |> put_change(:section_id, get_field(changeset, :section_id) || patch["section_id"])
        |> put_change(:exercise_id, get_field(changeset, :exercise_id) || patch["exercise_id"])

      _invalid ->
        add_error(changeset, :change, "is not a valid change")
    end
  end

  defp validate_has_content(changeset) do
    if get_field(changeset, :body) || get_field(changeset, :change) ||
         (get_field(changeset, :tags) || []) != [],
       do: changeset,
       else: add_error(changeset, :body, "write something, add a tag or record a change")
  end

  defp normalize_tags(tags) when is_list(tags),
    do:
      tags |> Enum.map(&blank_to_nil/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.take(20)

  defp normalize_tags(_tags), do: []

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
