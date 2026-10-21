defmodule Palee.Partners.Domain.MessagePolicy do
  @moduledoc """
  The pair's conversation (ADR-169 §7). Pure: body length, cursor paging
  (newest first) and a plan's snapshot of a class.
  """

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

  @doc "What a plan message keeps of a class, so it renders without Scheduling."
  def plan_snapshot(slot) do
    %{
      "class_id" => slot.id,
      "name" => slot_name(slot),
      "scheduled_at" => DateTime.to_iso8601(slot.scheduled_at),
      "duration_minutes" => slot.duration_minutes
    }
  end

  defp slot_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp slot_name(%{class_type: %{name: name}}) when is_binary(name), do: name
  defp slot_name(_slot), do: nil
end
