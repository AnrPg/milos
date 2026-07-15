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
  def add_participant(thread_id, user_id) do
    %Participant{}
    |> Participant.changeset(%{thread_id: thread_id, user_id: user_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:thread_id, :user_id])
  end

  @impl true
  def mark_read(thread_id, user_id, message_id) do
    Participant
    |> where([p], p.thread_id == ^thread_id and p.user_id == ^user_id)
    |> Repo.update_all(set: [last_read_message_id: message_id])

    :ok
  end

  @impl true
  def count_unread_threads(user_id) do
    latest_msg_subq =
      from m in Message,
        distinct: m.thread_id,
        order_by: [asc: m.thread_id, desc: m.inserted_at],
        select: %{thread_id: m.thread_id, id: m.id}

    Participant
    |> where([p], p.user_id == ^user_id)
    |> join(:inner, [p], lm in subquery(latest_msg_subq), on: lm.thread_id == p.thread_id)
    |> where([p, lm], is_nil(p.last_read_message_id) or p.last_read_message_id != lm.id)
    |> select([p], count(p.thread_id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp maybe_filter_context(query, nil), do: query

  defp maybe_filter_context(query, context_type) do
    where(query, [t], t.context_type == ^context_type)
  end

  defp last_message_query do
    Message
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
  end
end
