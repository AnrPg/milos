defmodule MilosTraining.Journal.Domain.FeedCursor do
  @moduledoc """
  Keyset cursor of the journal feed (ADR-139). Items are ordered newest
  first by `(occurred_at, kind, id)`; a cursor is the last item a page
  returned, and the next page holds everything strictly after it.

  Every source table holds one kind, so the tuple comparison becomes a
  per-source bound on `(occurred_at, id)` that the store can index.
  """

  alias MilosTraining.Journal.Domain.Visibility

  @type t :: %{at: DateTime.t(), kind: String.t(), id: String.t()}

  def encode(%{occurred_at: %DateTime{} = at, kind: kind, id: id}),
    do: Base.url_encode64("#{DateTime.to_iso8601(at)}|#{kind}|#{id}", padding: false)

  def decode(nil), do: {:ok, nil}
  def decode(""), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [at, kind, id] <- String.split(raw, "|"),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         true <- kind in Visibility.kinds(),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, %{at: at, kind: kind, id: id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}

  @doc """
  The bound a source of `kind` applies for a cursor:
  `:none`, `{:at_most, at}`, `{:before, at}` or `{:before_id, at, id}`.
  """
  def bound(_kind, nil), do: :none
  def bound(kind, %{at: at, kind: cursor_kind}) when kind < cursor_kind, do: {:at_most, at}
  def bound(kind, %{at: at, kind: kind, id: id}), do: {:before_id, at, id}
  def bound(_kind, %{at: at}), do: {:before, at}

  @doc "Newest first, ties broken by kind then id, as the cursor expects."
  def sort(items),
    do:
      Enum.sort_by(
        items,
        &{DateTime.to_unix(&1.occurred_at, :microsecond), &1.kind, &1.id},
        :desc
      )
end
