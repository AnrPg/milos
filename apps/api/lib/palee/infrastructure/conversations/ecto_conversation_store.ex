defmodule Palee.Infrastructure.Conversations.EctoConversationStore do
  @moduledoc "Ecto adapter of person conversations (ADR-193 §3)."

  @behaviour Palee.Conversations.Ports.ConversationStore

  import Ecto.Query

  alias Palee.Conversations.{Conversation, Message}
  alias Palee.Repo

  @impl true
  def get(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Conversation, id)
      :error -> nil
    end
  end

  @impl true
  def get_between(_context, a, b), do: Repo.get_by(Conversation, user_a_id: a, user_b_id: b)

  @impl true
  def insert_or_get(context, attrs) do
    attrs
    |> Conversation.create_changeset()
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_a_id, :user_b_id])
    |> case do
      {:ok, %Conversation{id: nil}} ->
        {:ok, get_between(context, attrs.user_a_id, attrs.user_b_id)}

      {:ok, conversation} ->
        {:ok, conversation}

      {:error, %Ecto.Changeset{}} ->
        {:error, :not_found}
    end
  end

  @impl true
  def update(_context, conversation, changes) do
    conversation
    |> Conversation.change_changeset(changes)
    |> Repo.update()
  end

  @impl true
  def append_message(_context, conversation, attrs, changes) do
    Repo.transaction(fn ->
      with {:ok, message} <- attrs |> Message.changeset() |> Repo.insert(),
           {:ok, conversation} <-
             conversation |> Conversation.change_changeset(changes) |> Repo.update() do
        {message, conversation}
      else
        {:error, %Ecto.Changeset{errors: errors}} ->
          if Keyword.has_key?(errors, :author_id),
            do: Repo.rollback(:duplicate_operation),
            else: Repo.rollback(:invalid_message)
      end
    end)
    |> case do
      {:ok, {message, conversation}} -> {:ok, message, conversation}
      {:error, reason} -> {:error, reason}
    end
  rescue
    # Row security refuses the insert when either person blocked the other.
    error in Postgrex.Error ->
      if error.postgres[:code] == :insufficient_privilege,
        do: {:error, :not_found},
        else: reraise(error, __STACKTRACE__)
  end

  @impl true
  def get_message_by_operation(_context, author_id, operation_id),
    do: Repo.get_by(Message, author_id: author_id, client_operation_id: operation_id)

  @impl true
  def list_for(_context, user_id, folder, cursor, limit) do
    Conversation
    |> where(
      [c],
      (c.user_a_id == ^user_id and c.a_folder == ^folder) or
        (c.user_b_id == ^user_id and c.b_folder == ^folder)
    )
    |> where([c], not is_nil(c.last_message_at) or c.started_by_id == ^user_id)
    |> conversation_cursor(cursor)
    |> order_by([c],
      desc: fragment("COALESCE(?, ?)", c.last_message_at, c.inserted_at),
      desc: c.id
    )
    |> limit(^limit)
    |> Repo.all()
  end

  defp conversation_cursor(query, nil), do: query

  defp conversation_cursor(query, {at, id}) do
    where(
      query,
      [c],
      fragment("COALESCE(?, ?)", c.last_message_at, c.inserted_at) < ^at or
        (fragment("COALESCE(?, ?)", c.last_message_at, c.inserted_at) == ^at and c.id < ^id)
    )
  end

  @impl true
  def last_messages(_context, []), do: %{}

  def last_messages(_context, ids) do
    Message
    |> where([m], m.conversation_id in ^ids)
    |> distinct([m], m.conversation_id)
    |> order_by([m], asc: m.conversation_id, desc: m.inserted_at, desc: m.id)
    |> Repo.all()
    |> Map.new(&{&1.conversation_id, &1})
  end

  @impl true
  def list_messages(_context, conversation_id, cursor, limit) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> message_cursor(cursor)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp message_cursor(query, nil), do: query

  defp message_cursor(query, {at, id}),
    do: where(query, [m], m.inserted_at < ^at or (m.inserted_at == ^at and m.id < ^id))

  @impl true
  def unread_counts(_context, user_id) do
    Conversation
    |> where([c], c.user_a_id == ^user_id or c.user_b_id == ^user_id)
    |> where([c], not is_nil(c.last_message_at) and c.last_author_id != ^user_id)
    |> select([c], %{
      folder:
        fragment(
          "CASE WHEN ? = ? THEN ? ELSE ? END",
          c.user_a_id,
          type(^user_id, :binary_id),
          c.a_folder,
          c.b_folder
        ),
      read_at:
        fragment(
          "CASE WHEN ? = ? THEN ? ELSE ? END",
          c.user_a_id,
          type(^user_id, :binary_id),
          c.a_read_at,
          c.b_read_at
        ),
      last_message_at: c.last_message_at
    })
    |> subquery()
    |> where([u], u.folder in ["inbox", "requests"])
    |> where([u], is_nil(u.read_at) or u.last_message_at > u.read_at)
    |> group_by([u], u.folder)
    |> select([u], {u.folder, count()})
    |> Repo.all()
    |> Map.new()
    |> then(&Map.merge(%{"inbox" => 0, "requests" => 0}, &1))
  end
end
