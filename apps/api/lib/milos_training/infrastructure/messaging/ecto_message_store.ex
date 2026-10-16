defmodule MilosTraining.Infrastructure.Messaging.EctoMessageStore do
  @behaviour MilosTraining.Messaging.Ports.MessageStore

  import Ecto.Query

  alias MilosTraining.Messaging.{Message, Participant, Thread}
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
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

    Repo.transaction(fn ->
      case insert_message(message_changeset, attrs) do
        {:created, message} ->
          case Repo.insert(job) do
            {:ok, _job} -> message
            {:error, reason} -> Repo.rollback(reason)
          end

        {:existing, message} ->
          message

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_messages(thread_id, params) do
    limit = Map.fetch!(params, :limit)
    before_id = Map.get(params, :before_id)

    Message
    |> scoped_to_tenant()
    |> where([m], m.thread_id == ^thread_id)
    |> maybe_before(before_id)
    |> order_by([m], desc: m.sequence_number)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  @impl true
  def get_message(id) do
    Message |> scoped_to_tenant() |> Repo.get(id)
  end

  @impl true
  def list_recent_coaching_messages(user_id, limit) do
    Message
    |> scoped_to_tenant()
    |> join(:inner, [message], thread in Thread, on: thread.id == message.thread_id)
    |> join(:inner, [_message, thread], participant in Participant,
      on: participant.thread_id == thread.id
    )
    |> where(
      [message, thread, participant],
      participant.user_id == ^user_id and thread.context_type == :direct and
        message.message_type == :coaching_message
    )
    |> order_by([message], desc: message.sequence_number)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def list_recent_coaching_messages_for_organization(user_id, limit) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        Message
        |> join(:inner, [message], thread in Thread, on: thread.id == message.thread_id)
        |> join(:inner, [_message, thread], participant in Participant,
          on: participant.thread_id == thread.id
        )
        |> where(
          [message, thread, participant],
          participant.user_id == ^user_id and thread.context_type == :direct and
            message.message_type == :coaching_message and
            message.organization_id == ^organization_id
        )
        |> order_by([message], desc: message.sequence_number)
        |> limit(^limit)
        |> Repo.all()

      _missing_scope ->
        []
    end
  end

  defp insert_message(
         changeset,
         %{sender_id: sender_id, client_operation_id: operation_id}
       )
       when not is_nil(operation_id) do
    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:sender_id, :client_operation_id],
           returning: true
         ) do
      {:ok, %{sequence_number: nil}} ->
        {:existing,
         Message
         |> scoped_to_tenant()
         |> Repo.get_by!(sender_id: sender_id, client_operation_id: operation_id)}

      {:ok, message} ->
        {:created, message}

      error ->
        error
    end
  end

  defp insert_message(changeset, _attrs) do
    case Repo.insert(changeset) do
      {:ok, message} -> {:created, message}
      error -> error
    end
  end

  defp maybe_before(query, nil), do: query

  defp maybe_before(query, before_id) do
    message = Message |> scoped_to_tenant() |> Repo.get(before_id)

    if message do
      where(query, [m], m.sequence_number < ^message.sequence_number)
    else
      query
    end
  end

  # ADR-098: direct threads whose latest message is a client's, i.e. the
  # client is waiting for staff to answer.
  @impl true
  def list_awaiting_staff_reply(staff_ids) do
    latest =
      Message
      |> scoped_to_tenant()
      |> join(:inner, [message], thread in Thread, on: thread.id == message.thread_id)
      |> where(
        [message, thread],
        thread.context_type == :direct and message.message_type != :system
      )
      |> distinct([message], message.thread_id)
      |> order_by([message], asc: message.thread_id, desc: message.sequence_number)
      |> select([message], %{
        message_id: message.id,
        thread_id: message.thread_id,
        sender_id: message.sender_id,
        sent_at: message.inserted_at
      })

    from(latest_message in subquery(latest),
      where: latest_message.sender_id not in ^staff_ids,
      order_by: [asc: latest_message.sent_at]
    )
    |> Repo.all()
  end

  @impl true
  def count_sent(sender_id, message_type, since) do
    Message
    |> scoped_to_tenant()
    |> where(
      [message],
      message.sender_id == ^sender_id and message.message_type == ^message_type and
        message.inserted_at >= ^since
    )
    |> select([message], count(message.id))
    |> Repo.one()
  end

  # Direct threads a coach is in whose latest message is from one of their
  # clients: the client is waiting for an answer.
  @impl true
  def count_awaiting_reply(coach_id, client_ids) do
    latest =
      Message
      |> scoped_to_tenant()
      |> join(:inner, [message], thread in Thread, on: thread.id == message.thread_id)
      |> join(:inner, [_message, thread], participant in Participant,
        on: participant.thread_id == thread.id and participant.user_id == ^coach_id
      )
      |> where(
        [message, thread],
        thread.context_type == :direct and message.message_type != :system
      )
      |> distinct([message], message.thread_id)
      |> order_by([message], asc: message.thread_id, desc: message.sequence_number)
      |> select([message], %{sender_id: message.sender_id})

    from(latest_message in subquery(latest),
      where: latest_message.sender_id in ^client_ids,
      select: count()
    )
    |> Repo.one()
  end

  defp scoped_to_tenant(query) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        where(query, [row], row.organization_id == ^organization_id)

      _missing_scope ->
        where(query, [row], false)
    end
  end
end
