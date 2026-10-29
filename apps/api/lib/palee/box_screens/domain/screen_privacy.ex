defmodule Palee.BoxScreens.Domain.ScreenPrivacy do
  @moduledoc """
  What a wall screen may say about people (ADR-253, GDPR data
  minimisation), pure. A TV is read by everyone in the room, so:

    * a person is shown by the first word of their display name only;
    * people who hide from members (`hide_from_members`) and guest or trial
      seats are only counted, never named;
    * only active bookings (approved) are shown; waitlists only as a count.
  """

  @doc "The first word of a display name, or nil."
  def first_name(name) when is_binary(name) do
    case name |> String.trim() |> String.split(~r/\s+/u, parts: 2) do
      [""] -> nil
      [first | _rest] -> String.slice(first, 0, 24)
    end
  end

  def first_name(_name), do: nil

  @doc """
  A class's bookings as the screen shows them:
  `%{count, capacity, waitlist, names, unnamed}`. `names` are first names of
  approved members who do not hide, in booking order; `unnamed` counts the
  rest of the approved seats (hidden people, guests, trials, no name).
  """
  def bookings(bookings, capacity, hidden_ids, names_by_id) do
    approved =
      bookings
      |> Enum.filter(&(&1.status in [:approved, "approved"]))
      |> Enum.sort_by(& &1.inserted_at, &not_later?/2)

    names =
      approved
      |> Enum.filter(&(&1.kind == "member" and not MapSet.member?(hidden_ids, &1.user_id)))
      |> Enum.map(&first_name(Map.get(names_by_id, &1.user_id)))
      |> Enum.reject(&is_nil/1)

    %{
      count: length(approved),
      capacity: capacity,
      waitlist: Enum.count(bookings, &(&1.status in [:waitlisted, "waitlisted"])),
      names: names,
      unnamed: length(approved) - length(names)
    }
  end

  defp not_later?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) != :gt

  defp not_later?(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: NaiveDateTime.compare(a, b) != :gt

  defp not_later?(a, b), do: a <= b

  @doc "Whom a booking names (members only), for loading their names."
  def nameable_user_ids(bookings) do
    bookings
    |> Enum.filter(&(&1.status in [:approved, "approved"] and &1.kind == "member"))
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&is_nil/1)
  end
end
