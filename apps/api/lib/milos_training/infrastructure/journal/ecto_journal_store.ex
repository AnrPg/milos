defmodule MilosTraining.Infrastructure.Journal.EctoJournalStore do
  @behaviour MilosTraining.Journal.Ports.JournalStore

  import Ecto.Query

  alias MilosTraining.Infrastructure.Journal.{FeedBound, FeedScope}
  alias MilosTraining.Journal.{CoachRead, Comment, Note, VisibilityDefault}
  alias MilosTraining.Repo

  @impl true
  def list_defaults(user_id) do
    VisibilityDefault
    |> where([default], default.user_id == ^user_id)
    |> select([default], {default.kind, default.visibility})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def put_default(user_id, kind, rung) do
    %{user_id: user_id, kind: kind, visibility: rung}
    |> VisibilityDefault.changeset()
    |> Repo.insert(
      on_conflict: {:replace, [:visibility, :updated_at]},
      conflict_target: [:user_id, :kind]
    )
    |> case do
      {:ok, _default} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def create_note(attrs) do
    attrs
    |> Note.create_changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  @impl true
  def update_note(id, user_id, attrs, lock_version) do
    case live_note(id, user_id) do
      nil ->
        {:error, :not_found}

      note ->
        # Without a version the edit applies to the note as it is now.
        note
        |> Map.put(:lock_version, lock_version || note.lock_version)
        |> Note.update_changeset(attrs)
        |> Repo.update(stale_error_field: :lock_version)
        |> case do
          {:error, %Ecto.Changeset{errors: [lock_version: _error]}} -> {:error, :stale}
          other -> normalize_result(other)
        end
    end
  end

  @impl true
  def delete_note(id, user_id, now) do
    case live_note(id, user_id) do
      nil -> {:error, :not_found}
      note -> note |> Note.delete_changeset(now) |> Repo.update() |> normalize_result()
    end
  end

  @impl true
  def get_note_for_user(id, user_id) do
    case live_note(id, user_id) do
      nil -> nil
      note -> normalize(note)
    end
  end

  @impl true
  def set_note_visibility(id, user_id, rung) do
    case live_note(id, user_id) do
      nil -> {:error, :not_found}
      note -> note |> Note.visibility_changeset(rung) |> Repo.update() |> normalize_result()
    end
  end

  @impl true
  def move_notes(user_id, from, to) do
    {count, _rows} =
      Note
      |> where([note], note.user_id == ^user_id and is_nil(note.deleted_at))
      |> where([note], not is_nil(note.organization_id))
      |> where([note], note.journal_visibility in ^from)
      |> Repo.update_all(set: [journal_visibility: to, updated_at: DateTime.utc_now()])

    count
  end

  @impl true
  def list_note_items(user_id, bound, limit, scope) do
    Note
    |> where([note], is_nil(note.deleted_at))
    |> FeedScope.apply(user_id, scope)
    |> FeedBound.apply(:written_at, bound)
    |> order_by([note], desc: note.written_at, desc: note.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  # Runs in the coach's tenant session: the coach read policy admits only
  # notes of that gym whose rung reaches the coach.
  @impl true
  def list_coach_visible_notes(user_id, organization_id) do
    Note
    |> where([note], note.user_id == ^user_id and note.organization_id == ^organization_id)
    |> where([note], is_nil(note.deleted_at))
    |> where(
      [note],
      fragment("milos_journal_visibility_reaches_coach(?)", note.journal_visibility)
    )
    |> order_by([note], desc: note.written_at, desc: note.id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def record_coach_reads([]), do: :ok

  def record_coach_reads(rows) do
    now = DateTime.utc_now()

    entries =
      Enum.map(rows, fn row ->
        row
        |> Map.take([:organization_id, :reader_user_id, :owner_user_id, :entry_kind, :entry_id])
        |> Map.merge(%{id: Ecto.UUID.generate(), read_at: now, inserted_at: now})
      end)

    {_count, _rows} = Repo.insert_all(CoachRead, entries)
    :ok
  end

  # Σχόλια (ADR-140 §1). A save is an upsert: by the comment's id when the
  # owner already has it, else by the change key of a structured change on
  # the same entry, else a new comment.
  @impl true
  def save_comment(%{user_id: user_id} = attrs) do
    case existing_comment(attrs) do
      nil ->
        attrs |> Comment.create_changeset() |> Repo.insert() |> normalize_comment_result()

      %Comment{user_id: ^user_id, entry_kind: kind, entry_id: entry_id} = comment
      when kind == attrs.entry_kind and entry_id == attrs.entry_id ->
        comment |> Comment.update_changeset(attrs) |> Repo.update() |> normalize_comment_result()

      %Comment{} ->
        {:error, :comment_conflict}
    end
  end

  @impl true
  def delete_comment(id, user_id, now) do
    case live_comment(id) do
      %Comment{user_id: ^user_id} = comment ->
        comment |> Comment.delete_changeset(now) |> Repo.update() |> normalize_comment_result()

      _missing ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_comments(_entry_kind, []), do: []

  def list_comments(entry_kind, entry_ids) do
    Comment
    |> where([comment], comment.entry_kind == ^entry_kind and comment.entry_id in ^entry_ids)
    |> where([comment], is_nil(comment.deleted_at))
    |> order_by([comment], asc: comment.written_at, asc: comment.id)
    |> Repo.all()
    |> Enum.map(&normalize_comment/1)
  end

  @impl true
  def list_changes_since(user_id, %DateTime{} = since) do
    Comment
    |> where([comment], comment.user_id == ^user_id and is_nil(comment.deleted_at))
    |> where([comment], not is_nil(comment.change) and comment.written_at >= ^since)
    |> order_by([comment], asc: comment.written_at)
    |> Repo.all()
    |> Enum.map(&normalize_comment/1)
  end

  @impl true
  def transaction(fun) do
    # Inside an outer transaction (an entry saved with its comments) the
    # outer one decides; a nested rollback would poison it.
    if Repo.in_transaction?(), do: fun.(), else: transact(fun)
  end

  defp transact(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def entry_owner(entry_kind, entry_id) do
    with {:ok, uuid} <- Ecto.UUID.dump(entry_id),
         %{rows: [[user_id, organization_id]]} <-
           Repo.query!(
             "SELECT user_id, organization_id FROM milos_journal_entry_owner($1, $2)",
             [entry_kind, uuid]
           ) do
      %{user_id: load_uuid(user_id), organization_id: load_uuid(organization_id)}
    else
      _missing -> nil
    end
  end

  defp load_uuid(nil), do: nil
  defp load_uuid(binary), do: Ecto.UUID.load!(binary)

  defp existing_comment(attrs) do
    by_id = Map.get(attrs, :id) && live_comment(attrs.id)

    by_id ||
      case Map.get(attrs, :change) do
        %{"patch_id" => key} when is_binary(key) ->
          Comment
          |> where([comment], comment.entry_kind == ^attrs.entry_kind)
          |> where([comment], comment.entry_id == ^attrs.entry_id and comment.change_key == ^key)
          |> where([comment], is_nil(comment.deleted_at) and comment.user_id == ^attrs.user_id)
          |> Repo.one()

        _no_change ->
          nil
      end
  end

  defp live_comment(id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Comment
      |> where([comment], comment.id == ^id and is_nil(comment.deleted_at))
      |> Repo.one()
    else
      :error -> nil
    end
  end

  defp normalize_comment_result({:ok, comment}), do: {:ok, normalize_comment(comment)}
  defp normalize_comment_result(error), do: error

  defp normalize_comment(%Comment{} = comment) do
    comment
    |> Map.from_struct()
    |> Map.drop([:__meta__, :deleted_at, :change_key, :inserted_at])
  end

  defp live_note(id, user_id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Note
      |> where([note], note.id == ^id and note.user_id == ^user_id and is_nil(note.deleted_at))
      |> Repo.one()
    else
      :error -> nil
    end
  end

  defp normalize_result({:ok, note}), do: {:ok, normalize(note)}
  defp normalize_result(error), do: error

  defp normalize(%Note{} = note) do
    note
    |> Map.from_struct()
    |> Map.drop([:__meta__, :deleted_at])
  end
end
