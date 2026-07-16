defmodule MilosTraining.Infrastructure.Messaging.EctoThreadStore do
  @behaviour MilosTraining.Messaging.Ports.ThreadStore

  import Ecto.Query

  alias MilosTraining.Messaging.{Message, Participant, Thread}
  alias MilosTraining.Repo

  @impl true
  def get_thread(id) do
    Repo.get(Thread, id)
  end

  @impl true
  def get_thread_with_participants(id) do
    Thread
    |> where([t], t.id == ^id)
    |> preload(:participants)
    |> Repo.one()
  end

  @impl true
  def find_direct_thread(user_id_a, user_id_b) do
    participant_ids = [user_id_a, user_id_b]

    thread_ids_for_a =
      Participant
      |> where([p], p.user_id == ^user_id_a)
      |> select([p], p.thread_id)

    thread_ids_for_b =
      Participant
      |> where([p], p.user_id == ^user_id_b)
      |> select([p], p.thread_id)

    Thread
    |> where([t], t.context_type == :direct)
    |> where([t], t.id in subquery(thread_ids_for_a))
    |> where([t], t.id in subquery(thread_ids_for_b))
    |> join(:left, [t], p in assoc(t, :participants))
    |> group_by([t, _p], t.id)
    |> having([_t, p], count(p.id) == ^length(participant_ids))
    |> order_by([t, _p], asc: t.inserted_at, asc: t.id)
    |> limit(1)
    |> preload(:participants)
    |> Repo.one()
  end

  @impl true
  def find_context_thread(context_type, context_id) do
    Thread
    |> where([t], t.context_type == ^context_type and t.context_id == ^context_id)
    |> preload(:participants)
    |> Repo.one()
  end

  @impl true
  def list_threads_for_user(user_id, context_type) do
    thread_ids =
      Participant
      |> where([p], p.user_id == ^user_id)
      |> select([p], p.thread_id)

    base = Thread |> where([t], t.id in subquery(thread_ids))

    base
    |> maybe_filter_context(context_type)
    |> order_by([t], desc: t.inserted_at)
    |> preload([:participants, messages: ^last_message_query()])
    |> Repo.all()
  end

  @impl true
  def create_thread(attrs) do
    %Thread{}
    |> Thread.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def get_or_create_thread(attrs, participant_ids) do
    Repo.transaction(fn ->
      thread = find_legacy_direct_thread(attrs, participant_ids) || insert_or_get_thread(attrs)

      participant_ids
      |> Enum.uniq()
      |> Enum.each(fn user_id ->
        %Participant{}
        |> Participant.changeset(%{thread_id: thread.id, user_id: user_id})
        |> Repo.insert!(on_conflict: :nothing, conflict_target: [:thread_id, :user_id])
      end)

      thread
      |> Repo.preload(:participants, force: true)
    end)
    |> case do
      {:ok, thread} -> {:ok, thread}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def add_participant(thread_id, user_id) do
    %Participant{}
    |> Participant.changeset(%{thread_id: thread_id, user_id: user_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:thread_id, :user_id])
  end

  @impl true
  def mark_read(thread_id, user_id, message_id) do
    Repo.transaction(fn ->
      participant =
        Participant
        |> where([p], p.thread_id == ^thread_id and p.user_id == ^user_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      target =
        Message
        |> where([m], m.id == ^message_id and m.thread_id == ^thread_id)
        |> Repo.one()

      cond do
        is_nil(participant) ->
          Repo.rollback(:not_found)

        is_nil(target) ->
          Repo.rollback(:invalid_message)

        is_nil(participant.last_read_message_id) ->
          advance_read_pointer(participant, target)

        true ->
          current = Repo.get(Message, participant.last_read_message_id)

          if later_message?(target, current) do
            advance_read_pointer(participant, target)
          else
            participant.last_read_message_id
          end
      end
    end)
    |> case do
      {:ok, effective_message_id} -> {:ok, effective_message_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def count_unread_threads(user_id) do
    Participant
    |> where([p], p.user_id == ^user_id)
    |> join(:left, [p], lr in Message, on: lr.id == p.last_read_message_id)
    |> join(:inner, [p, _lr], m in Message,
      on: m.thread_id == p.thread_id and m.sender_id != ^user_id
    )
    |> where([p, lr, m], is_nil(p.last_read_message_id) or m.sequence_number > lr.sequence_number)
    |> select([p], count(p.thread_id, :distinct))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp maybe_filter_context(query, nil), do: query

  defp maybe_filter_context(query, context_type) do
    where(query, [t], t.context_type == ^context_type)
  end

  defp last_message_query do
    Message
    |> order_by([m], desc: m.sequence_number)
    |> limit(1)
  end

  defp insert_or_get_thread(%{context_type: :direct, direct_key: direct_key} = attrs) do
    insert_or_get_thread(attrs, [:direct_key], fn ->
      Repo.get_by!(Thread, direct_key: direct_key)
    end)
  end

  defp insert_or_get_thread(%{context_type: context_type, context_id: context_id} = attrs) do
    conflict_target =
      {:unsafe_fragment, "(context_type, context_id) WHERE context_type != 'direct'"}

    insert_or_get_thread(attrs, conflict_target, fn ->
      Repo.get_by!(Thread, context_type: context_type, context_id: context_id)
    end)
  end

  defp insert_or_get_thread(attrs, conflict_target, fetch_existing) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    id = Ecto.UUID.generate()

    row =
      attrs
      |> Map.put(:id, id)
      |> Map.put(:inserted_at, now)

    case Repo.insert_all(Thread, [row],
           on_conflict: :nothing,
           conflict_target: conflict_target,
           returning: [:id]
         ) do
      {1, _rows} -> Repo.get!(Thread, id)
      {0, _rows} -> fetch_existing.()
    end
  end

  defp advance_read_pointer(participant, message) do
    participant
    |> Ecto.Changeset.change(last_read_message_id: message.id)
    |> Repo.update!()

    message.id
  end

  defp later_message?(_target, nil), do: true

  defp later_message?(target, %{thread_id: thread_id}) when target.thread_id != thread_id,
    do: true

  defp later_message?(target, current) do
    target.sequence_number > current.sequence_number
  end

  defp find_legacy_direct_thread(%{context_type: :direct, direct_key: direct_key}, [a, b]) do
    case find_direct_thread(a, b) do
      %{direct_key: nil} = thread ->
        thread
        |> Ecto.Changeset.change(direct_key: direct_key)
        |> Repo.update!()

      thread ->
        thread
    end
  end

  defp find_legacy_direct_thread(_attrs, _participant_ids), do: nil
end
