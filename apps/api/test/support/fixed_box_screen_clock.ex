defmodule Palee.TestSupport.FixedBoxScreenClock do
  @moduledoc """
  A box screen clock (ADR-253) that stands where a test puts it:
  `put(at)` until the test ends, else the real time.
  """

  @behaviour Palee.BoxScreens.Ports.Clock

  @key :box_screen_fixed_now

  @impl true
  def now, do: Application.get_env(:palee, @key) || DateTime.utc_now()

  @doc "Use this clock at `at` for the rest of the test (`ExUnit` `on_exit` restores)."
  def put(%DateTime{} = at) do
    previous = Application.get_env(:palee, :box_screen_clock)
    Application.put_env(:palee, :box_screen_clock, __MODULE__)
    Application.put_env(:palee, @key, at)

    ExUnit.Callbacks.on_exit({__MODULE__, :restore}, fn ->
      Application.put_env(:palee, :box_screen_clock, previous)
      Application.delete_env(:palee, @key)
    end)

    :ok
  end

  @doc "Moves the clock (after `put/1`)."
  def set(%DateTime{} = at), do: Application.put_env(:palee, @key, at)
end
