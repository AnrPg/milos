defmodule Palee.Infrastructure.BoxScreens.SystemClock do
  @moduledoc "The real clock for box screens (ADR-253)."

  @behaviour Palee.BoxScreens.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
