defmodule MilosTraining.Application.BuddyMessages do
  @moduledoc """
  The buddy conversation (ADR-160 §2): one thread per buddy link, owned by
  Buddies and account-scoped, so two buddies can always talk whether or not
  they share a gym. Only the link's two people read it (row security); a
  message can be written only while the link is active, so an ended link's
  thread stays readable but read-only. Support replies post into it too.

  Each message notifies the other person once (`buddy_message`); a support
  reply notifies once as `support_reply` instead, never both.
  """

  alias MilosTraining.Application.Buddies, as: BuddyPages
  alias MilosTraining.Application.BuddyRealtime
  alias MilosTraining.{Buddies, Identity, Notifications}

  @doc "A page of the link's messages, newest first, with the next (older) cursor."
  def list(%{user_id: user_id} = context, link_id, params, now \\ DateTime.utc_now()) do
    limit = Buddies.message_page_limit(param(params, "limit"))

    with {:ok, link} <- fetch_link(context, link_id),
         {:ok, cursor} <- Buddies.decode_message_cursor(param(params, "cursor")) do
      rows = Buddies.list_messages(context, link.id, cursor, limit + 1)
      {page, next_cursor} = Buddies.message_page(rows, limit)
      people = people(link)

      {:ok,
       %{
         messages: Enum.map(page, &present(&1, user_id, people)),
         next_cursor: next_cursor,
         read_only: Buddies.messages_read_only?(link, now),
         unread: Map.get(Buddies.unread_counts(context, user_id, [link.id]), link.id, 0)
       }}
    end
  end

  @doc "Writes a message into an active link and tells the other person once."
  def post(%{user_id: user_id} = context, link_id, params, now \\ DateTime.utc_now()) do
    with {:ok, link} <- fetch_link(context, link_id),
         :ok <- Buddies.can_post_message?(link, now),
         {:ok, body} <- Buddies.normalize_message_body(param(params, "body")),
         {:ok, message} <- insert(context, link, body) do
      notify(context, link, message)
      BuddyRealtime.message_created(link)
      {:ok, present(message, user_id, people(link))}
    end
  end

  @doc "Marks the other person's messages read; answers how many changed."
  def mark_read(%{user_id: user_id} = context, link_id, now \\ DateTime.utc_now()) do
    with {:ok, link} <- fetch_link(context, link_id) do
      read = Buddies.mark_messages_read(context, link.id, user_id, now)
      if read > 0, do: BuddyRealtime.messages_read(link)
      {:ok, %{read: read}}
    end
  end

  @doc false
  # A support reply's message: no notification of its own (the reply sends one).
  def post_reply(context, link, body) do
    with {:ok, message} <- insert(context, link, body) do
      BuddyRealtime.message_created(link)
      {:ok, message}
    end
  end

  defp insert(%{user_id: user_id} = context, link, body) do
    Buddies.insert_message(context, %{
      link_id: link.id,
      user_id: link.user_id,
      buddy_user_id: link.buddy_user_id,
      author_id: user_id,
      body: body
    })
  end

  defp notify(%{user_id: user_id} = context, link, message) do
    Notifications.dispatch_event(:buddy_message, %{
      user_id: Buddies.other_party(link, user_id),
      link_id: link.id,
      message_id: message.id,
      author_id: user_id,
      author_nickname: author_nickname(context),
      dedupe_key: "buddy_message:#{message.id}"
    })
  end

  defp author_nickname(%{user_id: user_id} = context) do
    case Map.get(context, :account) || Identity.find_by_id(user_id) do
      %{} = account -> BuddyPages.nickname(account)
      _none -> nil
    end
  end

  defp fetch_link(%{user_id: user_id} = context, link_id) do
    case Buddies.get_link(context, link_id) do
      %{buddy_user_id: buddy} = link when is_binary(buddy) ->
        if Buddies.link_party?(link, user_id), do: {:ok, link}, else: {:error, :not_found}

      _missing ->
        {:error, :not_found}
    end
  end

  defp people(link) do
    [link.user_id, link.buddy_user_id] |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
  end

  @doc false
  def present(message, viewer_id, people) do
    %{
      id: message.id,
      link_id: message.link_id,
      body: message.body,
      mine: message.author_id == viewer_id,
      author: BuddyPages.person(people[message.author_id]),
      created_at: message.inserted_at,
      read_at: message.read_at
    }
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  defp param(_params, _key), do: nil
end
