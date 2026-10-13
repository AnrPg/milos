defmodule MilosTraining.Infrastructure.Coaching.EctoNoteStore do
  @moduledoc "Ecto adapter for private coach notes (ADR-101)."

  @behaviour MilosTraining.Coaching.Ports.NoteStore

  import Ecto.Query

  alias MilosTraining.Coaching.{Note, NoteRead}
  alias MilosTraining.Repo

  @impl true
  def create(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Note.changeset()
    |> Repo.insert()
    |> result()
  end

  @impl true
  def get(%{organization_id: organization_id}, id) do
    case fetch(organization_id, id) do
      nil -> nil
      note -> normalize(note)
    end
  end

  @impl true
  def update(%{organization_id: organization_id}, id, attrs) do
    case fetch(organization_id, id) do
      nil -> {:error, :not_found}
      note -> note |> Note.changeset(Map.take(attrs, [:body])) |> Repo.update() |> result()
    end
  end

  @impl true
  def delete(%{organization_id: organization_id}, id) do
    case fetch(organization_id, id) do
      nil -> {:error, :not_found}
      note -> with {:ok, _deleted} <- Repo.delete(note), do: :ok
    end
  end

  @impl true
  def list_for_client(%{organization_id: organization_id}, client_id) do
    Note
    |> where([n], n.organization_id == ^organization_id and n.client_user_id == ^client_id)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def record_reads(_context, [], _reader_id, _at), do: :ok

  def record_reads(%{organization_id: organization_id}, note_ids, reader_id, at) do
    rows =
      Enum.map(note_ids, fn note_id ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          note_id: note_id,
          reader_user_id: reader_id,
          read_at: at,
          inserted_at: at
        }
      end)

    {_count, _} = Repo.insert_all(NoteRead, rows)
    :ok
  end

  @impl true
  def list_reads(%{organization_id: organization_id}, coach_id) do
    NoteRead
    |> join(:inner, [r], n in Note, on: n.id == r.note_id)
    |> where([r, n], r.organization_id == ^organization_id and n.coach_user_id == ^coach_id)
    |> order_by([r], desc: r.read_at)
    |> limit(200)
    |> select([r, n], %{
      id: r.id,
      note_id: r.note_id,
      client_user_id: n.client_user_id,
      reader_user_id: r.reader_user_id,
      read_at: r.read_at
    })
    |> Repo.all()
  end

  defp fetch(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Note |> where([n], n.organization_id == ^organization_id and n.id == ^id) |> Repo.one()

      :error ->
        nil
    end
  end

  defp normalize(note),
    do: Map.take(note, [:id, :coach_user_id, :client_user_id, :body, :inserted_at, :updated_at])

  defp result({:ok, note}), do: {:ok, normalize(note)}
  defp result(error), do: error
end
