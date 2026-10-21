defmodule Palee.Body.Domain.SnapshotCursor do
  @moduledoc "Keyset cursor of a snapshot list, newest first by `(taken_at, id)` (ADR-158)."

  @default_limit 20
  @max_limit 100

  def encode(%{taken_at: %DateTime{} = at, id: id}),
    do: Base.url_encode64("#{DateTime.to_iso8601(at)}|#{id}", padding: false)

  def decode(nil), do: {:ok, nil}
  def decode(""), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(raw, "|"),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, %{taken_at: at, id: id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}

  def limit(nil), do: @default_limit
  def limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)

  def limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit(limit)
      _invalid -> @default_limit
    end
  end

  def limit(_value), do: @default_limit

  @doc "A page from `limit + 1` rows: the rows to show and the next cursor."
  def page(rows, limit) do
    {shown, rest} = Enum.split(rows, limit)
    next = if rest != [] and shown != [], do: encode(List.last(shown))
    {shown, next}
  end
end
