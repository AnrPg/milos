defmodule Palee.BoxScreens.Ports.Clock do
  @moduledoc """
  The time box screens run on (ADR-253), injected so tests can stand at
  any moment of a class. The adapter is chosen in config
  (`:box_screen_clock`).
  """

  @callback now() :: DateTime.t()
end
