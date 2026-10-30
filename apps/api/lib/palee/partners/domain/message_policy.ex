defmodule Palee.Partners.Domain.MessagePolicy do
  @moduledoc """
  The pair's conversation (ADR-169 §7, ADR-280). Pure: body length, cursor
  paging (newest first) and a plan's snapshot (a class, event or trial).
  """

  @body_max 2000
  @page_default 30
  @page_max 100
  @plan_kinds ~w(class event trial)
  @plan_text_max 200

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

  @doc "An optional note with a plan: nil when blank."
  def normalize_note(nil), do: {:ok, nil}

  def normalize_note(body) when is_binary(body) do
    if String.trim(body) == "", do: {:ok, nil}, else: normalize_body(body)
  end

  def normalize_note(_body), do: {:error, :message_body_required}

  def page_limit(nil), do: @page_default
  def page_limit(value) when is_integer(value), do: value |> max(1) |> min(@page_max)

  def page_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> page_limit(n)
      _other -> @page_default
    end
  end

  def page_limit(_value), do: @page_default

  def encode_cursor(%{inserted_at: %DateTime{} = at, id: id}),
    do: Base.url_encode64("#{DateTime.to_iso8601(at)}|#{id}", padding: false)

  def decode_cursor(cursor) when cursor in [nil, ""], do: {:ok, nil}

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

  @doc """
  What a plan message keeps (ADR-280 §1): a snapshot of a class, an event
  or a trial class, so it renders without the context it came from.
  `plan` is `%{kind: "class" | "event" | "trial", id:, title:, starts_at:,
  place:}`; `place` may be nil.
  """
  def plan_snapshot(plan) when is_map(plan) do
    with kind when kind in @plan_kinds <- field(plan, :kind),
         {:ok, id} <- Ecto.UUID.cast(field(plan, :id) || ""),
         title when is_binary(title) and title != "" <- field(plan, :title),
         {:ok, starts_at} <- starts_at(field(plan, :starts_at)),
         place when is_nil(place) or is_binary(place) <- field(plan, :place) do
      {:ok,
       %{
         "kind" => kind,
         "id" => id,
         "title" => String.slice(title, 0, @plan_text_max),
         "starts_at" => DateTime.to_iso8601(starts_at),
         "place" => place && String.slice(place, 0, @plan_text_max)
       }}
    else
      _invalid -> {:error, :invalid_partner_plan}
    end
  end

  def plan_snapshot(_plan), do: {:error, :invalid_partner_plan}

  def plan_kinds, do: @plan_kinds

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp starts_at(%DateTime{} = at), do: {:ok, at}

  defp starts_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _error -> :error
    end
  end

  defp starts_at(_value), do: :error
end
