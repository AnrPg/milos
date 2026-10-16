defmodule MilosTraining.Infrastructure.Journal.EctoJournalStore do
  @behaviour MilosTraining.Journal.Ports.JournalStore

  import Ecto.Query

  alias MilosTraining.Infrastructure.Journal.FeedBound
  alias MilosTraining.Journal.{CoachRead, Note, VisibilityDefault}
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
        note
        |> Map.put(:lock_version, lock_version)
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
  def list_note_items(user_id, bound, limit) do
    Note
    |> where([note], note.user_id == ^user_id and is_nil(note.deleted_at))
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
