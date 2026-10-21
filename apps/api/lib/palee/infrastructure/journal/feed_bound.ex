defmodule Palee.Infrastructure.Journal.FeedBound do
  @moduledoc "Applies a `FeedCursor.bound/2` to an Ecto query on one source table."

  import Ecto.Query

  def apply(query, _at_field, :none), do: query

  def apply(query, at_field, {:at_most, at}),
    do: where(query, [row], field(row, ^at_field) <= ^at)

  def apply(query, at_field, {:before, at}),
    do: where(query, [row], field(row, ^at_field) < ^at)

  def apply(query, at_field, {:before_id, at, id}) do
    where(
      query,
      [row],
      field(row, ^at_field) < ^at or
        (field(row, ^at_field) == ^at and row.id < type(^id, :binary_id))
    )
  end
end
