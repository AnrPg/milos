defmodule Palee.Application.PersonConversations do
  @moduledoc """
  Person-to-person conversations (ADR-193 §3), in the acting person's
  personal session: no gym is needed or consulted. Anyone may write to
  anyone they can see who has not blocked them (or been blocked by them);
  where the message lands for the recipient is the pure
  `ConversationPolicy`'s call, from the facts between the two people:
  Buddies, a shared gym or open club, or the recipient following the sender
  reach the inbox; anyone else waits in message requests.

  Each message notifies the recipient once: `person_message` in the inbox,
  `message_request` (once per conversation) in requests, nothing when the
  recipient declined.
  """

  alias Palee.Application.ConversationRealtime
  alias Palee.{Community, Conversations, Identity, Notifications}

  @folders ~w(inbox requests)

  @doc "The person's conversations in a folder (`inbox` by default), latest first."
  def list(%{user_id: user_id} = context, params) do
    folder = param(params, "folder") || "inbox"
    limit = Conversations.page_limit(param(params, "limit"))

    with true <- folder in @folders || {:error, :bad_request},
         {:ok, cursor} <- Conversations.decode_cursor(param(params, "cursor")) do
      rows = Conversations.list_for(context, user_id, folder, cursor, limit + 1)
      {page, rest} = Enum.split(rows, limit)

      {:ok,
       %{
         conversations: present_all(context, page, user_id),
         next_cursor:
           case {rest, List.last(page)} do
             {[_ | _], %{} = last} ->
               Conversations.encode_cursor(last.last_message_at || last.inserted_at, last.id)

             _end ->
               nil
           end
       }}
    end
  end

  @doc "How many conversations hold unread messages, in the inbox and in requests."
  def unread_count(%{user_id: user_id} = context) do
    counts = Conversations.unread_counts(context, user_id)
    {:ok, %{inbox: Map.get(counts, "inbox", 0), requests: Map.get(counts, "requests", 0)}}
  end

  @doc "Opens (or finds) the conversation with another person."
  def open(%{user_id: user_id} = context, other_id) do
    with {:ok, other_id} <- uuid(other_id),
         true <- other_id != user_id || {:error, :self_conversation},
         :ok <- reachable(context, other_id) do
      existing = between(context, user_id, other_id)

      conversation =
        existing ||
          create(context, user_id, other_id, facts(context, other_id))

      case conversation do
        {:error, reason} -> {:error, reason}
        {:ok, conversation} -> {:ok, present(context, conversation, user_id)}
        conversation -> {:ok, present(context, conversation, user_id)}
      end
    end
  end

  @doc "One conversation as the person sees it."
  def show(%{user_id: user_id} = context, id) do
    with {:ok, conversation} <- fetch(context, id),
         do: {:ok, present(context, conversation, user_id)}
  end

  @doc "A page of messages, newest first, with the next (older) cursor."
  def messages(%{user_id: user_id} = context, id, params) do
    limit = Conversations.page_limit(param(params, "limit"))

    with {:ok, conversation} <- fetch(context, id),
         {:ok, cursor} <- Conversations.decode_cursor(param(params, "cursor")) do
      rows = Conversations.list_messages(context, conversation.id, cursor, limit + 1)
      {page, rest} = Enum.split(rows, limit)

      {:ok,
       %{
         messages: Enum.map(page, &present_message(&1, user_id)),
         next_cursor:
           if(rest != [] and page != [],
             do: Conversations.encode_cursor(List.last(page).inserted_at, List.last(page).id)
           )
       }}
    end
  end

  @doc """
  Writes a message. A retry with the same `client_operation_id` answers the
  message it already wrote.
  """
  def post(%{user_id: user_id} = context, id, params, now \\ DateTime.utc_now()) do
    operation_id = param(params, "client_operation_id")

    with {:ok, conversation} <- fetch(context, id),
         {:ok, body} <- Conversations.normalize_body(param(params, "body")),
         {:ok, operation_id} <- optional_uuid(operation_id) do
      case operation_id && Conversations.get_message_by_operation(context, user_id, operation_id) do
        %{} = message -> {:ok, present_message(message, user_id)}
        _new -> write(context, conversation, body, operation_id, now)
      end
    end
  end

  def read(%{user_id: user_id} = context, id, now \\ DateTime.utc_now()) do
    with {:ok, conversation} <- fetch(context, id),
         {:ok, conversation} <-
           Conversations.update(
             context,
             conversation,
             Conversations.mark_read(conversation, user_id, now)
           ) do
      ConversationRealtime.read(conversation)
      {:ok, present(context, conversation, user_id)}
    end
  end

  def accept(%{user_id: user_id} = context, id) do
    with {:ok, conversation} <- fetch(context, id),
         {:ok, conversation} <-
           Conversations.update(
             context,
             conversation,
             Conversations.accept(conversation, user_id)
           ) do
      ConversationRealtime.folder_changed(conversation)
      {:ok, present(context, conversation, user_id)}
    end
  end

  def decline(%{user_id: user_id} = context, id) do
    with {:ok, conversation} <- fetch(context, id),
         {:ok, changes} <- Conversations.decline(conversation, user_id),
         {:ok, _conversation} <- Conversations.update(context, conversation, changes) do
      :ok
    end
  end

  defp write(%{user_id: user_id} = context, conversation, body, operation_id, now) do
    other_id = Conversations.other(conversation, user_id)

    with :ok <- reachable(context, other_id) do
      facts = facts(context, other_id)
      changes = Conversations.after_message(conversation, user_id, facts, now)

      attrs = %{
        conversation_id: conversation.id,
        user_a_id: conversation.user_a_id,
        user_b_id: conversation.user_b_id,
        author_id: user_id,
        body: body,
        client_operation_id: operation_id
      }

      case Conversations.append_message(context, conversation, attrs, changes) do
        {:ok, message, updated} ->
          notify(context, updated, message, other_id)
          ConversationRealtime.message_created(updated, message)
          {:ok, present_message(message, user_id)}

        {:error, :duplicate_operation} ->
          {:ok,
           context
           |> Conversations.get_message_by_operation(user_id, operation_id)
           |> present_message(user_id)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp notify(context, conversation, message, recipient_id) do
    payload = %{
      user_id: recipient_id,
      conversation_id: conversation.id,
      message_id: message.id,
      author_id: message.author_id,
      author_nickname: nickname(context, message.author_id)
    }

    case Conversations.folder(conversation, recipient_id) do
      "inbox" ->
        Notifications.dispatch_event(
          :person_message,
          Map.put(payload, :dedupe_key, "person_message:#{message.id}")
        )

      "requests" ->
        Notifications.dispatch_event(:message_request, payload)

      _declined ->
        :ok
    end
  end

  defp create(%{user_id: user_id} = context, user_id, other_id, facts) do
    {a, b} = Conversations.pair(user_id, other_id)
    {a_folder, b_folder} = Conversations.new_folders(user_id, other_id, facts)

    Conversations.insert_or_get(context, %{
      user_a_id: a,
      user_b_id: b,
      started_by_id: user_id,
      a_folder: a_folder,
      b_folder: b_folder
    })
  end

  defp between(context, user_id, other_id) do
    {a, b} = Conversations.pair(user_id, other_id)
    Conversations.get_between(context, a, b)
  end

  # Mock people stay inside their demo business (ADR-184); a block either
  # way makes the person unreachable, and looks like nobody is there.
  defp reachable(%{user_id: user_id} = context, other_id) do
    cond do
      is_nil(Identity.find_by_id(other_id)) -> {:error, :not_found}
      not Identity.visible_to?(other_id, user_id) -> {:error, :not_found}
      other_id in Community.blocked_user_ids(context) -> {:error, :not_found}
      true -> :ok
    end
  end

  defp facts(context, other_id) do
    Map.get(Community.person_relations(context, [other_id]), other_id, %{})
  end

  defp fetch(%{user_id: user_id} = context, id) do
    case Conversations.get(context, id) do
      %{} = conversation ->
        if Conversations.party?(conversation, user_id) and
             Conversations.folder(conversation, user_id) != "declined",
           do: {:ok, conversation},
           else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  defp present_all(context, conversations, user_id) do
    last = Conversations.last_messages(context, Enum.map(conversations, & &1.id))
    others = Enum.map(conversations, &Conversations.other(&1, user_id))
    people = others |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
    relations = Community.person_relations(context, others)

    Enum.map(conversations, fn conversation ->
      other_id = Conversations.other(conversation, user_id)

      shape(conversation, user_id, people[other_id], relations[other_id], last[conversation.id])
    end)
  end

  defp present(context, conversation, user_id),
    do: hd(present_all(context, [conversation], user_id))

  defp shape(conversation, user_id, person, relation, last) do
    %{
      id: conversation.id,
      person: person_ref(person, Conversations.other(conversation, user_id)),
      folder: Conversations.folder(conversation, user_id),
      buddy: Conversations.buddies?(relation || %{}),
      started_by_me: conversation.started_by_id == user_id,
      unread: Conversations.unread?(conversation, user_id),
      last_message_at: conversation.last_message_at,
      last_message: last && present_message(last, user_id)
    }
  end

  defp person_ref(nil, id), do: %{id: id, nickname: nil, handle: nil, avatar_url: nil}

  defp person_ref(person, _id),
    do: %{
      id: person.id,
      nickname: person.nickname,
      handle: Map.get(person, :handle),
      avatar_url: Map.get(person, :avatar_url)
    }

  defp present_message(message, viewer_id) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      author_id: message.author_id,
      body: message.body,
      mine: message.author_id == viewer_id,
      client_operation_id: message.client_operation_id,
      created_at: message.inserted_at
    }
  end

  defp nickname(context, user_id) do
    case Map.get(context, :account) || Identity.find_by_id(user_id) do
      %{nickname: nickname} -> nickname
      _none -> nil
    end
  end

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp optional_uuid(nil), do: {:ok, nil}
  defp optional_uuid(""), do: {:ok, nil}

  defp optional_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :bad_request}
    end
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  defp param(_params, _key), do: nil
end
