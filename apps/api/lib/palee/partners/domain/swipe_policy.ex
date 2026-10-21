defmodule Palee.Partners.Domain.SwipePolicy do
  @moduledoc """
  Swiping (ADR-169 §4). Pure. At most 200 swipes in any 24 hours; a like or
  a pass, nothing else. Nobody learns who liked them before it is mutual.
  """

  alias Palee.Partners.Swipe

  @daily_limit 200

  def daily_limit, do: @daily_limit
  def directions, do: Swipe.directions()

  def normalize_direction(direction) when is_binary(direction) do
    if direction in Swipe.directions(), do: {:ok, direction}, else: {:error, :invalid_direction}
  end

  def normalize_direction(_direction), do: {:error, :invalid_direction}

  def window_start(now), do: DateTime.add(now, -86_400, :second)

  def check_rate(count) when count < @daily_limit, do: :ok
  def check_rate(_count), do: {:error, :partner_swipe_limit}

  def remaining(count), do: max(@daily_limit - count, 0)

  @doc "A like answered by a like makes a match."
  def mutual?("like", %{direction: "like"}), do: true
  def mutual?(_direction, _reverse), do: false
end
