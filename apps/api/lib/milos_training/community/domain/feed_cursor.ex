defmodule MilosTraining.Community.Domain.FeedCursor do
  @moduledoc "Opaque keyset cursor over posts, newest first: `(inserted_at, id)` (ADR-138)."

  def encode(%{inserted_at: %DateTime{} = at, id: id}),
    do: Base.url_encode64("#{DateTime.to_iso8601(at)}|#{id}", padding: false)

  def decode(nil), do: {:ok, nil}
  def decode(""), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {at, id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}

  @doc "Newest first, ties broken by id, as the store pages them."
  def sort(posts),
    do: Enum.sort_by(posts, &{&1.inserted_at, &1.id}, &(compare(&1, &2) != :lt))

  defp compare({at_a, id_a}, {at_b, id_b}) do
    case DateTime.compare(at_a, at_b) do
      :eq -> if(id_a == id_b, do: :eq, else: if(id_a > id_b, do: :gt, else: :lt))
      other -> other
    end
  end
end
