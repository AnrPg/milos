defmodule Palee.Conversations.Domain.ConversationPolicy do
  @moduledoc """
  Person-to-person conversations (ADR-193 §3). Pure rules: the pair's order,
  each side's fields, where a message lands for its recipient, what
  replying, accepting and declining do, unread state, message bodies and
  cursor paging (newest first).

  Where a message lands for its recipient:

  - Buddies (they follow each other), a shared active gym or open club, or
    the recipient follows the sender: the recipient's `inbox`;
  - anyone else: `requests`, until the recipient accepts or replies;
  - a conversation the recipient declined stays `declined` (never shown to
    them again, the sender is not told) unless the relationship now
    qualifies for the inbox.
  """

  @folders ~w(inbox requests declined)
  @listed ~w(inbox requests)
  @body_max 2000
  @page_default 30
  @page_max 100

  def folders, do: @folders
  def listed_folders, do: @listed
  def body_max, do: @body_max

  @doc "The pair in stored order (`user_a_id < user_b_id`)."
  def pair(one, other) when one < other, do: {one, other}
  def pair(one, other), do: {other, one}

  @doc "Which side of the conversation `user_id` is, or nil."
  def side(%{user_a_id: user_id}, user_id) when is_binary(user_id), do: :a
  def side(%{user_b_id: user_id}, user_id) when is_binary(user_id), do: :b
  def side(_conversation, _user_id), do: nil

  def party?(conversation, user_id), do: side(conversation, user_id) != nil

  @doc "The other person of the pair."
  def other(%{user_a_id: user_id, user_b_id: other}, user_id), do: other
  def other(%{user_b_id: user_id, user_a_id: other}, user_id), do: other

  def folder(conversation, user_id),
    do: Map.get(conversation, field(side(conversation, user_id), :folder))

  def read_at(conversation, user_id),
    do: Map.get(conversation, field(side(conversation, user_id), :read_at))

  @doc "The column of a side's field (`:a_folder`, `:b_read_at`, ...)."
  def field(:a, :folder), do: :a_folder
  def field(:b, :folder), do: :b_folder
  def field(:a, :read_at), do: :a_read_at
  def field(:b, :read_at), do: :b_read_at

  @doc """
  Whether the recipient's inbox takes the sender's messages. `facts` are
  from the sender's side: `i_follow` (sender follows recipient),
  `follows_me` (recipient follows sender) and `shares_club`.
  """
  def inbox?(facts) do
    Map.get(facts, :follows_me, false) or Map.get(facts, :shares_club, false)
  end

  @doc "Buddies follow each other actively (ADR-193 §1)."
  def buddies?(facts), do: Map.get(facts, :i_follow, false) and Map.get(facts, :follows_me, false)

  @doc "The recipient's folder when the conversation starts."
  def initial_folder(facts), do: if(inbox?(facts), do: "inbox", else: "requests")

  @doc "The folders of a new conversation `starter_id` opens with `other_id`."
  def new_folders(starter_id, other_id, facts) do
    {a, _b} = pair(starter_id, other_id)
    recipient = initial_folder(facts)
    if a == starter_id, do: {"inbox", recipient}, else: {recipient, "inbox"}
  end

  @doc """
  The changes a message from `author_id` makes at `now`: the latest message,
  the author's own read mark, the author's folder (replying accepts a
  request, writing again undoes a decline) and the recipient's folder.
  """
  def after_message(conversation, author_id, facts, now) do
    author = side(conversation, author_id)
    recipient = if author == :a, do: :b, else: :a
    current = Map.get(conversation, field(recipient, :folder))

    %{
      field(author, :folder) => "inbox",
      field(author, :read_at) => now,
      field(recipient, :folder) => recipient_folder(current, facts),
      last_message_at: now,
      last_author_id: author_id
    }
  end

  defp recipient_folder("inbox", _facts), do: "inbox"
  defp recipient_folder(current, facts), do: if(inbox?(facts), do: "inbox", else: current)

  def accept(conversation, user_id), do: %{field(side(conversation, user_id), :folder) => "inbox"}

  def decline(conversation, user_id) do
    case folder(conversation, user_id) do
      "requests" -> {:ok, %{field(side(conversation, user_id), :folder) => "declined"}}
      _other -> {:error, :not_a_request}
    end
  end

  def mark_read(conversation, user_id, now),
    do: %{field(side(conversation, user_id), :read_at) => now}

  @doc "A conversation shows in a person's lists once it has a message, or when they started it."
  def listed?(conversation, user_id) do
    folder(conversation, user_id) in @listed and
      (not is_nil(conversation.last_message_at) or conversation.started_by_id == user_id)
  end

  @doc "Whether the person has a message from the other side they have not read."
  def unread?(%{last_message_at: nil}, _user_id), do: false

  def unread?(conversation, user_id) do
    conversation.last_author_id != user_id and
      case read_at(conversation, user_id) do
        nil -> true
        at -> DateTime.compare(conversation.last_message_at, at) == :gt
      end
  end

  @doc "A message body: trimmed, 1..2000 characters."
  def normalize_body(body) when is_binary(body) do
    case String.trim(body) do
      "" ->
        {:error, :message_body_required}

      text ->
        if String.length(text) <= @body_max,
          do: {:ok, text},
          else: {:error, :message_too_long_body}
    end
  end

  def normalize_body(_body), do: {:error, :message_body_required}

  @doc "Page size: 30 by default, at most 100."
  def page_limit(nil), do: @page_default
  def page_limit(value) when is_integer(value), do: value |> max(1) |> min(@page_max)

  def page_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> page_limit(n)
      _other -> @page_default
    end
  end

  def page_limit(_value), do: @page_default

  @doc "An opaque cursor for the row after which the next (older) page starts."
  def encode_cursor(%DateTime{} = at, id),
    do: Base.url_encode64("#{DateTime.to_iso8601(at)}|#{id}", padding: false)

  def decode_cursor(nil), do: {:ok, nil}
  def decode_cursor(""), do: {:ok, nil}

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {at, id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode_cursor(_cursor), do: {:error, :invalid_cursor}
end
