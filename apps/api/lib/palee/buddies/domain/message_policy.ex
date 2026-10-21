defmodule Palee.Buddies.Domain.MessagePolicy do
  @moduledoc """
  The buddy conversation (ADR-160 §2): one thread per buddy link, owned by
  the Buddies context and independent of any gym. Pure rules: body length,
  who may write (an active link only; an ended link's thread is read-only),
  the text a support reply posts, and cursor paging (newest first).
  """

  alias Palee.Buddies.Domain.LinkPolicy

  @body_max 2000
  @page_default 30
  @page_max 100

  def body_max, do: @body_max

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

  @doc "Whether `user_id` is one of the link's two people."
  def party?(%{user_id: user_id}, user_id) when is_binary(user_id), do: true
  def party?(%{buddy_user_id: user_id}, user_id) when is_binary(user_id), do: true
  def party?(_link, _user_id), do: false

  @doc "Messages are written only while the link is active."
  def can_post?(link, now) do
    if LinkPolicy.effective_status(link, now) == "active",
      do: :ok,
      else: {:error, :buddy_link_read_only}
  end

  def read_only?(link, now), do: LinkPolicy.effective_status(link, now) != "active"

  @doc """
  What a support reply posts into the conversation: the quick reply's text,
  then the buddy's own words when given; a `text` reply is the words alone.
  """
  def reply_body("text", _quick_text, text), do: text
  def reply_body(_kind, quick_text, nil), do: quick_text
  def reply_body(_kind, quick_text, text), do: quick_text <> "\n\n" <> text

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

  @doc "An opaque cursor for the message after which the next (older) page starts."
  def encode_cursor(%{inserted_at: %DateTime{} = at, id: id}),
    do: Base.url_encode64("#{DateTime.to_iso8601(at)}|#{id}", padding: false)

  def decode_cursor(nil), do: {:ok, nil}
  def decode_cursor(""), do: {:ok, nil}

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         {:ok, _uuid} <- Ecto.UUID.cast(id) do
      {:ok, %{inserted_at: at, id: id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode_cursor(_cursor), do: {:error, :invalid_cursor}

  @doc "Splits a fetched page (one extra row) into the page and the next cursor."
  def page(rows, limit) do
    {page, rest} = Enum.split(rows, limit)
    {page, if(rest != [] and page != [], do: encode_cursor(List.last(page)))}
  end
end
