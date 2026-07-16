defmodule MilosTraining.Infrastructure.Messaging.EctoMessageStore do
  @behaviour MilosTraining.Messaging.Ports.MessageStore

  import Ecto.Query

  alias MilosTraining.Messaging.{Message, Participant, Thread}
  alias MilosTraining.Repo
  alias MilosTraining.Workers.DispatchMessageJob

  @impl true
  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def create_message_with_delivery(attrs, delivery) do
    message_id = Ecto.UUID.generate()
    message_changeset = Message.changeset(%Message{id: message_id}, attrs)

    job =
      delivery
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put("message_id", message_id)
      |> DispatchMessageJob.new()

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:message, message_changeset)
    |> Ecto.Multi.insert(:delivery_job, job)
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message}} -> {:ok, message}
      {:error, :message, changeset, _changes} -> {:error, changeset}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  @impl true
  def list_messages(thread_id, params) do
    limit = Map.fetch!(params, :limit)
    before_id = Map.get(params, :before_id)

    Message
    |> where([m], m.thread_id == ^thread_id)
    |> maybe_before(before_id)
    |> order_by([m], desc: m.sequence_number)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  @impl true
  def get_message(id) do
    Repo.get(Message, id)
  end

  @impl true
  def list_recent_coaching_notes(user_id, limit) do
    Message
    |> join(:inner, [message], thread in Thread, on: thread.id == message.thread_id)
    |> join(:inner, [_message, thread], participant in Participant,
      on: participant.thread_id == thread.id
    )
    |> where(
      [message, thread, participant],
      participant.user_id == ^user_id and thread.context_type == :direct and
        message.message_type == :coaching_note
    )
    |> order_by([message], desc: message.sequence_number)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_before(query, nil), do: query

  defp maybe_before(query, before_id) do
    message = Repo.get(Message, before_id)

    if message do
      where(query, [m], m.sequence_number < ^message.sequence_number)
    else
      query
    end
  end
end
