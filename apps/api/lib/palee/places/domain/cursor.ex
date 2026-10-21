defmodule Palee.Places.Domain.Cursor do
  @moduledoc """
  Opaque «Δες όλα» cursors of each Γύρω μου kind (ADR-154), keyed on the
  kind's own order: events by start then id, boxes by trial rank, distance
  then id, clubs by distance then id, posts newest first.
  """

  @kinds ~w(events boxes clubs posts)
  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

  @doc "The cursor after `row` (the last row of a page)."
  def encode("events", %{starts_at: at, id: id}), do: token("events", [iso(at), id])

  def encode("boxes", %{rank: rank, distance_m: distance, organization_id: id}),
    do: token("boxes", [rank, distance, id])

  def encode("clubs", %{distance_m: distance, id: id}), do: token("clubs", [distance, id])
  def encode("posts", %{created_at: at, id: id}), do: token("posts", [iso(at), id])

  @doc "`{:ok, nil}` without a cursor, the kind's keys, or an error."
  def decode(_kind, nil), do: {:ok, nil}
  def decode(_kind, ""), do: {:ok, nil}

  def decode(kind, token) when kind in @kinds and is_binary(token) do
    with {:ok, json} <- Base.url_decode64(token, padding: false),
         {:ok, [^kind, values]} <- Jason.decode(json),
         {:ok, keys} <- keys(kind, values),
         true <- keys.id =~ @uuid do
      {:ok, keys}
    else
      _invalid -> {:error, [cursor: "is invalid"]}
    end
  end

  def decode(_kind, _token), do: {:error, [cursor: "is invalid"]}

  defp keys(kind, [at, id])
       when kind in ["events", "posts"] and is_binary(at) and is_binary(id) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> {:ok, %{at: at, id: id}}
      _invalid -> :error
    end
  end

  defp keys("boxes", [rank, distance, id])
       when rank in [0, 1] and is_number(distance) and is_binary(id),
       do: {:ok, %{rank: rank, distance_m: distance * 1.0, id: id}}

  defp keys("clubs", [distance, id]) when is_number(distance) and is_binary(id),
    do: {:ok, %{distance_m: distance * 1.0, id: id}}

  defp keys(_kind, _values), do: :error

  defp token(kind, values),
    do: [kind, values] |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
