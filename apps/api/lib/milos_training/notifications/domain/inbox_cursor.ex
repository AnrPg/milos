defmodule MilosTraining.Notifications.Domain.InboxCursor do
  @separator "|"

  def encode(nil), do: nil

  def encode(%{inserted_at: inserted_at, id: id}) when is_binary(id) do
    [DateTime.to_iso8601(inserted_at), id]
    |> Enum.join(@separator)
    |> Base.url_encode64(padding: false)
  end

  def decode(nil), do: {:ok, nil}
  def decode(""), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [inserted_at, id] <- String.split(decoded, @separator, parts: 2),
         {:ok, datetime, _offset} <- DateTime.from_iso8601(inserted_at) do
      {:ok, %{inserted_at: datetime, id: id}}
    else
      _error -> {:error, :invalid_cursor}
    end
  end
end
